use crate::types::{ArgSpec, ArgType, Snippet};
use anyhow::{Result, anyhow, bail};
use regex::Regex;
use serde_json::Value;
use std::{collections::BTreeMap, sync::LazyLock};

static PLACEHOLDER: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"\{\{\s*(json|raw)\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*\}\}").unwrap());

pub fn render(snippet: &Snippet, args: &serde_json::Map<String, Value>) -> Result<String> {
    let empty: BTreeMap<String, ArgSpec> = BTreeMap::new();
    let specs = snippet.frontmatter.args.as_ref().unwrap_or(&empty);

    let mut resolved: BTreeMap<String, Value> = BTreeMap::new();
    let mut missing: Vec<&str> = Vec::new();

    for (name, spec) in specs {
        if let Some(value) = args.get(name) {
            resolved.insert(name.clone(), coerce(name, value, spec)?);
        } else if let Some(default) = &spec.default {
            resolved.insert(name.clone(), default.clone());
        } else if !spec.optional.unwrap_or(false) {
            missing.push(name);
        }
    }
    if !missing.is_empty() {
        bail!("missing required args: {}", missing.join(", "));
    }

    let extras: Vec<&String> = args.keys().filter(|k| !specs.contains_key(*k)).collect();
    if !extras.is_empty() {
        bail!(
            "unknown args: {}",
            extras
                .iter()
                .map(|s| s.as_str())
                .collect::<Vec<_>>()
                .join(", ")
        );
    }

    let mut err: Option<anyhow::Error> = None;
    let out = PLACEHOLDER
        .replace_all(&snippet.body, |caps: &regex::Captures<'_>| {
            if err.is_some() {
                return String::new();
            }
            let mode = &caps[1];
            let key = &caps[2];
            let Some(value) = resolved.get(key) else {
                err = Some(anyhow!(
                    "placeholder {{{mode} {key}}} references undeclared arg '{key}'"
                ));
                return String::new();
            };
            match mode {
                "json" => serde_json::to_string(value).unwrap_or_else(|_| "null".to_string()),
                _ => match value {
                    Value::String(s) => s.clone(),
                    other => other.to_string(),
                },
            }
        })
        .to_string();

    if let Some(e) = err {
        return Err(e);
    }
    Ok(out)
}

fn coerce(name: &str, value: &Value, spec: &ArgSpec) -> Result<Value> {
    match spec.ty {
        ArgType::String => {
            if value.is_string() {
                Ok(value.clone())
            } else {
                Err(anyhow!("arg '{name}' must be a string"))
            }
        }
        ArgType::Number => {
            if value.is_number() {
                Ok(value.clone())
            } else {
                Err(anyhow!("arg '{name}' must be a number"))
            }
        }
        ArgType::Boolean => {
            if value.is_boolean() {
                Ok(value.clone())
            } else {
                Err(anyhow!("arg '{name}' must be a boolean"))
            }
        }
    }
}
