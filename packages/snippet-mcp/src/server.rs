use crate::refresh::refresh_executor;
use crate::render::render;
use crate::snippets::Registry;
use crate::types::{ArgSpec, SaveInput, Snippet, UpdateInput};
use rmcp::model::{
    CallToolRequestParams, CallToolResult, Content, ErrorData as McpError, Implementation,
    JsonObject, ListToolsResult, PaginatedRequestParams, ProtocolVersion, ServerCapabilities,
    ServerInfo, Tool,
};
use rmcp::service::RequestContext;
use rmcp::{RoleServer, ServerHandler};
use serde_json::{Map, Value, json};
use std::sync::Arc;

#[derive(Clone)]
pub struct SnippetServer {
    registry: Arc<Registry>,
}

impl SnippetServer {
    pub fn new(registry: Arc<Registry>) -> Self {
        Self { registry }
    }
}

impl ServerHandler for SnippetServer {
    fn get_info(&self) -> ServerInfo {
        let mut info = ServerInfo::default();
        info.protocol_version = ProtocolVersion::V_2025_06_18;
        info.capabilities = ServerCapabilities::builder().enable_tools().build();
        info.server_info = Implementation::new("snippet-mcp", env!("CARGO_PKG_VERSION"));
        info.instructions = Some(
            "Saved workflow snippets as searchable tools. Use _list/_get/_save/_update/_delete to manage.".into(),
        );
        info
    }

    async fn list_tools(
        &self,
        _request: Option<PaginatedRequestParams>,
        _context: RequestContext<RoleServer>,
    ) -> Result<ListToolsResult, McpError> {
        let snippets = self
            .registry
            .list()
            .map_err(|e| McpError::internal_error(format!("listing snippets: {e}"), None))?;
        let mut tools: Vec<Tool> = snippets.iter().map(snippet_tool).collect();
        tools.extend(management_tools());
        Ok(ListToolsResult {
            tools,
            ..Default::default()
        })
    }

    async fn call_tool(
        &self,
        request: CallToolRequestParams,
        _context: RequestContext<RoleServer>,
    ) -> Result<CallToolResult, McpError> {
        let args = request.arguments.unwrap_or_default();
        let name = request.name.as_ref();
        let result = self.dispatch(name, args).await;
        match result {
            Ok(text) => Ok(CallToolResult::success(vec![Content::text(text)])),
            Err(err) => Ok(CallToolResult::error(vec![Content::text(err.to_string())])),
        }
    }
}

impl SnippetServer {
    async fn dispatch(&self, name: &str, args: JsonObject) -> anyhow::Result<String> {
        match name {
            "_list" => {
                let snippets = self.registry.list()?;
                let json: Vec<_> = snippets
                    .iter()
                    .map(|s| {
                        json!({
                            "name": s.name,
                            "description": s.frontmatter.description,
                            "tags": s.frontmatter.tags.clone().unwrap_or_default(),
                            "kind": s.frontmatter.kind.unwrap_or_default().as_str(),
                        })
                    })
                    .collect();
                Ok(serde_json::to_string_pretty(&json)?)
            }
            "_get" => {
                let name = required_str(&args, "name")?;
                let s = self.registry.load(name)?;
                Ok(serde_json::to_string_pretty(&json!({
                    "name": s.name,
                    "frontmatter": s.frontmatter,
                    "body": s.body,
                }))?)
            }
            "_save" => {
                let input: SaveInput = serde_json::from_value(Value::Object(args))
                    .map_err(|e| anyhow::anyhow!("invalid _save args: {e}"))?;
                let saved = self.registry.save(input)?;
                wrap_write(saved).await
            }
            "_update" => {
                let input: UpdateInput = serde_json::from_value(Value::Object(args))
                    .map_err(|e| anyhow::anyhow!("invalid _update args: {e}"))?;
                let saved = self.registry.update(input)?;
                wrap_write(saved).await
            }
            "_delete" => {
                let name = required_str(&args, "name")?.to_string();
                self.registry.delete(&name)?;
                let r = refresh_executor().await;
                Ok(format!("deleted {name}; executor refresh: {}", r.detail))
            }
            _ => {
                let snippet = self.registry.load(name)?;
                render(&snippet, &args)
            }
        }
    }
}

async fn wrap_write(s: Snippet) -> anyhow::Result<String> {
    let r = refresh_executor().await;
    Ok(serde_json::to_string_pretty(&json!({
        "saved": { "name": s.name },
        "executor_refresh": if r.ok { "ok".to_string() } else { r.detail },
    }))?)
}

fn required_str<'a>(args: &'a JsonObject, field: &str) -> anyhow::Result<&'a str> {
    args.get(field)
        .and_then(|v| v.as_str())
        .filter(|s| !s.is_empty())
        .ok_or_else(|| anyhow::anyhow!("{field} must be a non-empty string"))
}

fn snippet_tool(s: &Snippet) -> Tool {
    let mut description = s.frontmatter.description.clone();
    if let Some(tags) = &s.frontmatter.tags {
        if !tags.is_empty() {
            description.push_str(&format!(" [tags: {}]", tags.join(", ")));
        }
    }
    let kind = s.frontmatter.kind.unwrap_or_default();
    description.push_str(&format!(
        " (kind: {}) — returns the rendered snippet body for use inside executor.execute.",
        kind.as_str()
    ));
    build_tool(
        s.name.clone(),
        description,
        args_to_schema(s.frontmatter.args.as_ref()),
    )
}

fn args_to_schema(args: Option<&std::collections::BTreeMap<String, ArgSpec>>) -> JsonObject {
    let mut properties = Map::new();
    let mut required: Vec<Value> = Vec::new();
    if let Some(args) = args {
        for (name, spec) in args {
            let mut p = Map::new();
            p.insert("type".into(), Value::String(spec.ty.as_str().into()));
            if let Some(desc) = &spec.description {
                p.insert("description".into(), Value::String(desc.clone()));
            }
            if let Some(default) = &spec.default {
                p.insert("default".into(), default.clone());
            }
            properties.insert(name.clone(), Value::Object(p));
            if !spec.optional.unwrap_or(false) && spec.default.is_none() {
                required.push(Value::String(name.clone()));
            }
        }
    }
    let mut schema = Map::new();
    schema.insert("type".into(), Value::String("object".into()));
    schema.insert("properties".into(), Value::Object(properties));
    if !required.is_empty() {
        schema.insert("required".into(), Value::Array(required));
    }
    schema.insert("additionalProperties".into(), Value::Bool(false));
    schema
}

fn obj(pairs: &[(&str, Value)]) -> Value {
    let mut m = Map::new();
    for (k, v) in pairs {
        m.insert((*k).into(), v.clone());
    }
    Value::Object(m)
}

fn management_tools() -> Vec<Tool> {
    let str_t = obj(&[("type", Value::String("string".into()))]);
    let bool_t = obj(&[("type", Value::String("boolean".into()))]);
    let str_arr_t = obj(&[
        ("type", Value::String("array".into())),
        ("items", str_t.clone()),
    ]);
    let kind_enum = obj(&[
        ("type", Value::String("string".into())),
        (
            "enum",
            Value::Array(vec![
                Value::String("code".into()),
                Value::String("instructions".into()),
            ]),
        ),
    ]);
    let args_t = obj(&[
        ("type", Value::String("object".into())),
        (
            "description",
            Value::String(
                "Map of arg name → { type: 'string'|'number'|'boolean', description?, optional?, default? }"
                    .into(),
            ),
        ),
        ("additionalProperties", Value::Bool(true)),
    ]);

    vec![
        tool(
            "_list",
            "List all snippets with their name, description, tags, and kind.",
            empty_obj_schema(),
        ),
        tool(
            "_get",
            "Return a snippet's raw frontmatter and body (unrendered).",
            object_schema(&[("name", &str_t)], &["name"]),
        ),
        tool(
            "_save",
            "Create a new snippet file. body may contain {{json arg}} or {{raw arg}} placeholders matching the declared args.",
            object_schema(
                &[
                    ("name", &str_t),
                    ("description", &str_t),
                    ("body", &str_t),
                    ("args", &args_t),
                    ("tags", &str_arr_t),
                    ("kind", &kind_enum),
                    ("overwrite", &bool_t),
                ],
                &["name", "description", "body"],
            ),
        ),
        tool(
            "_update",
            "Update an existing snippet. Any omitted field keeps its current value.",
            object_schema(
                &[
                    ("name", &str_t),
                    ("description", &str_t),
                    ("body", &str_t),
                    ("args", &args_t),
                    ("tags", &str_arr_t),
                    ("kind", &kind_enum),
                ],
                &["name"],
            ),
        ),
        tool(
            "_delete",
            "Delete a snippet file.",
            object_schema(&[("name", &str_t)], &["name"]),
        ),
    ]
}

fn tool(name: &'static str, description: &'static str, schema: JsonObject) -> Tool {
    build_tool(name.to_string(), description.to_string(), schema)
}

fn build_tool(name: String, description: String, schema: JsonObject) -> Tool {
    Tool::new(name, description, Arc::new(schema))
}

fn empty_obj_schema() -> JsonObject {
    let mut m = Map::new();
    m.insert("type".into(), Value::String("object".into()));
    m.insert("properties".into(), Value::Object(Map::new()));
    m.insert("additionalProperties".into(), Value::Bool(false));
    m
}

fn object_schema(props: &[(&str, &Value)], required: &[&str]) -> JsonObject {
    let mut properties = Map::new();
    for (k, v) in props {
        properties.insert((*k).into(), (*v).clone());
    }
    let mut m = Map::new();
    m.insert("type".into(), Value::String("object".into()));
    m.insert("properties".into(), Value::Object(properties));
    if !required.is_empty() {
        m.insert(
            "required".into(),
            Value::Array(
                required
                    .iter()
                    .map(|s| Value::String((*s).into()))
                    .collect(),
            ),
        );
    }
    m.insert("additionalProperties".into(), Value::Bool(false));
    m
}
