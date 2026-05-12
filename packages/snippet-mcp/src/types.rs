use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum ArgType {
    String,
    Number,
    Boolean,
}

impl ArgType {
    pub fn as_str(&self) -> &'static str {
        match self {
            ArgType::String => "string",
            ArgType::Number => "number",
            ArgType::Boolean => "boolean",
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ArgSpec {
    #[serde(rename = "type")]
    pub ty: ArgType,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub description: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub optional: Option<bool>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub default: Option<serde_json::Value>,
}

#[derive(Debug, Clone, Copy, Default, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum SnippetKind {
    #[default]
    Code,
    Instructions,
}

impl SnippetKind {
    pub fn as_str(&self) -> &'static str {
        match self {
            SnippetKind::Code => "code",
            SnippetKind::Instructions => "instructions",
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Frontmatter {
    pub description: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub args: Option<BTreeMap<String, ArgSpec>>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub tags: Option<Vec<String>>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub kind: Option<SnippetKind>,
}

#[derive(Debug, Clone)]
pub struct Snippet {
    pub name: String,
    pub frontmatter: Frontmatter,
    pub body: String,
}

#[derive(Debug, Clone, Deserialize)]
pub struct SaveInput {
    pub name: String,
    pub description: String,
    pub body: String,
    #[serde(default)]
    pub args: Option<BTreeMap<String, ArgSpec>>,
    #[serde(default)]
    pub tags: Option<Vec<String>>,
    #[serde(default)]
    pub kind: Option<SnippetKind>,
    #[serde(default)]
    pub overwrite: Option<bool>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct UpdateInput {
    pub name: String,
    #[serde(default)]
    pub description: Option<String>,
    #[serde(default)]
    pub body: Option<String>,
    #[serde(default)]
    pub args: Option<BTreeMap<String, ArgSpec>>,
    #[serde(default)]
    pub tags: Option<Vec<String>>,
    #[serde(default)]
    pub kind: Option<SnippetKind>,
}
