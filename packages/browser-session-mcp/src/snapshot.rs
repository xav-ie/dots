//! Accessibility tree as indented text. Cheap, human-readable, enough for an
//! agent to "see" the page without a screenshot round-trip.
use anyhow::{Context, Result};
use chromiumoxide::Page;
use chromiumoxide::cdp::browser_protocol::accessibility::{
    AxNode, AxNodeId, AxPropertyName, GetFullAxTreeParams,
};
use serde_json::Value;
use std::collections::HashMap;

pub async fn snapshot(page: &Page) -> Result<String> {
    let result = page
        .execute(GetFullAxTreeParams::default())
        .await
        .context("Accessibility.getFullAXTree")?;
    let nodes = &result.result.nodes;
    if nodes.is_empty() {
        return Ok("(empty accessibility tree)".to_string());
    }

    let by_id: HashMap<AxNodeId, &AxNode> = nodes.iter().map(|n| (n.node_id.clone(), n)).collect();
    let has_parent: std::collections::HashSet<AxNodeId> = nodes
        .iter()
        .flat_map(|n| n.child_ids.iter().flatten().cloned())
        .collect();
    let roots: Vec<&AxNode> = nodes
        .iter()
        .filter(|n| !has_parent.contains(&n.node_id))
        .collect();

    let mut lines = Vec::new();
    for root in roots {
        walk(root, &by_id, 0, &mut lines);
    }
    if lines.is_empty() {
        return Ok("(empty accessibility tree)".to_string());
    }
    Ok(lines.join("\n"))
}

fn walk<'a>(
    node: &'a AxNode,
    by_id: &HashMap<AxNodeId, &'a AxNode>,
    depth: usize,
    out: &mut Vec<String>,
) {
    if !node.ignored {
        if let Some(line) = format_node(node, depth) {
            out.push(line);
        }
    }
    let next_depth = if node.ignored { depth } else { depth + 1 };
    if let Some(child_ids) = node.child_ids.as_ref() {
        for child_id in child_ids {
            if let Some(child) = by_id.get(child_id) {
                walk(child, by_id, next_depth, out);
            }
        }
    }
}

fn format_node(node: &AxNode, depth: usize) -> Option<String> {
    let role = node
        .role
        .as_ref()
        .and_then(|v| v.value.as_ref())
        .and_then(|v| v.as_str())
        .unwrap_or("unknown");
    let name_str = node
        .name
        .as_ref()
        .and_then(|v| v.value.as_ref())
        .and_then(|v| v.as_str())
        .map(escape_name)
        .unwrap_or_default();
    let value_str = node
        .value
        .as_ref()
        .and_then(|v| v.value.as_ref())
        .map(format_value)
        .unwrap_or_default();
    let level_str = node
        .properties
        .iter()
        .flatten()
        .find(|p| matches!(p.name, AxPropertyName::Level))
        .and_then(|p| p.value.value.as_ref())
        .and_then(|v| v.as_i64())
        .map(|n| format!(" level={n}"))
        .unwrap_or_default();

    // Don't render entirely uninteresting nodes: no role, no name, no value.
    if role == "unknown" && name_str.is_empty() && value_str.is_empty() {
        return None;
    }
    let indent = "  ".repeat(depth);
    let name_part = if name_str.is_empty() {
        String::new()
    } else {
        format!(" \"{name_str}\"")
    };
    Some(format!("{indent}{role}{name_part}{value_str}{level_str}"))
}

fn format_value(v: &Value) -> String {
    match v {
        Value::Null => String::new(),
        _ => format!(" [value={}]", serde_json::to_string(v).unwrap_or_default()),
    }
}

fn escape_name(s: &str) -> String {
    // Slice on char boundary so non-ASCII accessibility names (em dashes,
    // smart quotes, CJK, etc.) don't panic mid-codepoint.
    let mut counted = s.char_indices();
    if counted.by_ref().nth(120).is_none() {
        return s.to_string();
    }
    let cut = s.char_indices().nth(117).map(|(i, _)| i).unwrap_or(s.len());
    format!("{}...", &s[..cut])
}
