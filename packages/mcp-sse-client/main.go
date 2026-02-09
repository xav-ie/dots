package main

import (
	"bufio"
	"bytes"
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

type sseURLParts struct {
	scheme string
	host   string
}

func parseSSEURL(raw string) (sseURLParts, error) {
	u, err := url.Parse(raw)
	if err != nil {
		return sseURLParts{}, err
	}
	return sseURLParts{scheme: u.Scheme, host: u.Host}, nil
}

// initCache stores cached MCP handshake responses for instant startup.
type initCache struct {
	Initialize json.RawMessage `json:"initialize"`
	ToolsList  json.RawMessage `json:"tools_list"`
}

func cacheFilePath(url string) string {
	dir := os.Getenv("XDG_CACHE_HOME")
	if dir == "" {
		home, _ := os.UserHomeDir()
		dir = filepath.Join(home, ".cache")
	}
	h := sha256.Sum256([]byte(url))
	return filepath.Join(dir, "mcp-sse-client", fmt.Sprintf("%x.json", h[:8]))
}

func loadCache(path string) *initCache {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil
	}
	var c initCache
	if json.Unmarshal(data, &c) != nil {
		return nil
	}
	if c.Initialize == nil || c.ToolsList == nil {
		return nil
	}
	return &c
}

func saveCache(path string, c *initCache) {
	os.MkdirAll(filepath.Dir(path), 0o755)
	data, _ := json.Marshal(c)
	os.WriteFile(path, data, 0o644)
}

type requestInfo struct {
	method string
	cached bool
}

func main() {
	var sseURL string
	stripCaps := map[string]bool{}
	noCache := false

	args := os.Args[1:]
	for i := 0; i < len(args); i++ {
		if args[i] == "--strip-capabilities" && i+1 < len(args) {
			i++
			for _, c := range strings.Split(args[i], ",") {
				stripCaps[strings.TrimSpace(c)] = true
			}
		} else if args[i] == "--no-cache" {
			noCache = true
		} else if !strings.HasPrefix(args[i], "--") {
			sseURL = args[i]
		}
	}

	if sseURL == "" {
		fmt.Fprintln(os.Stderr, "Usage: mcp-sse-client <sse-url> [--strip-capabilities resources,...] [--no-cache]")
		os.Exit(1)
	}

	// Load response cache
	cachePath := cacheFilePath(sseURL)
	var cache *initCache
	if !noCache {
		cache = loadCache(cachePath)
	}

	var (
		messageEndpoint string
		endpointReady   = make(chan struct{})
		pendingMu       sync.Mutex
		pending         []string

		// Track all requests by ID for cache building and suppression
		requests sync.Map // string(id) -> requestInfo

		// Accumulate real responses for cache update
		newCacheMu sync.Mutex
		newCache   initCache
	)

	// POST a JSON-RPC message to the server
	postMessage := func(jsonMsg string) {
		body := bytes.NewBufferString(jsonMsg)
		resp, err := http.Post(messageEndpoint, "application/json", body)
		if err != nil {
			fmt.Fprintf(os.Stderr, "POST error: %v\n", err)
			return
		}
		resp.Body.Close()
	}

	// Connect to SSE endpoint in background so cached responses are instant
	sseURL_parsed, err := parseSSEURL(sseURL)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Invalid URL: %v\n", err)
		os.Exit(1)
	}

	go func() {
		req, err := http.NewRequest("GET", sseURL, nil)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Invalid URL: %v\n", err)
			os.Exit(1)
		}
		req.Header.Set("Accept", "text/event-stream")
		req.Header.Set("Cache-Control", "no-cache")

		resp, err := http.DefaultClient.Do(req)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Connection error: %v\n", err)
			os.Exit(1)
		}
		if resp.StatusCode != 200 {
			fmt.Fprintf(os.Stderr, "SSE connection failed: %d\n", resp.StatusCode)
			os.Exit(1)
		}
		defer resp.Body.Close()

		scanner := bufio.NewScanner(resp.Body)
		scanner.Buffer(make([]byte, 0, 64*1024), 1024*1024)

		var currentEvent string
		var currentData strings.Builder

		for scanner.Scan() {
			line := scanner.Text()

			if strings.HasPrefix(line, "event:") {
				currentEvent = strings.TrimSpace(line[6:])
			} else if strings.HasPrefix(line, "data:") {
				value := line[5:]
				if strings.HasPrefix(value, " ") {
					value = value[1:]
				}
				if currentData.Len() > 0 {
					currentData.WriteByte('\n')
				}
				currentData.WriteString(value)
			} else if line == "" {
				data := currentData.String()
				currentData.Reset()

				switch currentEvent {
				case "endpoint":
					if strings.HasPrefix(data, "http") {
						messageEndpoint = data
					} else {
						messageEndpoint = fmt.Sprintf("%s://%s%s", sseURL_parsed.scheme, sseURL_parsed.host, data)
					}
					pendingMu.Lock()
					p := pending
					pending = nil
					pendingMu.Unlock()
					close(endpointReady)
					for _, msg := range p {
						postMessage(msg)
					}
				case "message", "":
					if data != "" {
						suppress := false

						// Check if this response was already served from cache
						if !noCache {
							var rpcResp struct {
								ID     json.RawMessage `json:"id,omitempty"`
								Result json.RawMessage `json:"result,omitempty"`
							}
							if json.Unmarshal([]byte(data), &rpcResp) == nil && rpcResp.ID != nil {
								idStr := string(rpcResp.ID)
								if val, ok := requests.LoadAndDelete(idStr); ok {
									info := val.(requestInfo)

									// Update cache with real response
									if rpcResp.Result != nil && (info.method == "initialize" || info.method == "tools/list") {
										newCacheMu.Lock()
										switch info.method {
										case "initialize":
											newCache.Initialize = rpcResp.Result
										case "tools/list":
											newCache.ToolsList = rpcResp.Result
										}
										if newCache.Initialize != nil && newCache.ToolsList != nil {
											saveCache(cachePath, &newCache)
										}
										newCacheMu.Unlock()
									}

									if info.cached {
										suppress = true
									}
								}
							}
						}

						if !suppress {
							if len(stripCaps) > 0 {
								data = maybeStripCapabilities(data, stripCaps)
							}
							fmt.Fprintln(os.Stdout, data)
						}
					}
				}
				currentEvent = ""
			}
		}
		os.Exit(0)
	}()

	// Read stdin and POST messages
	debug := os.Getenv("MCP_SSE_DEBUG") != ""
	var t0 time.Time
	if debug {
		t0 = time.Now()
		fmt.Fprintf(os.Stderr, "[mcp-sse] +%dms stdin reader starting (cache=%v)\n", 0, cache != nil)
	}
	scanner := bufio.NewScanner(os.Stdin)
	scanner.Buffer(make([]byte, 0, 64*1024), 1024*1024)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" {
			continue
		}

		if debug {
			var peek struct {
				Method string `json:"method"`
			}
			json.Unmarshal([]byte(line), &peek)
			fmt.Fprintf(os.Stderr, "[mcp-sse] +%dms recv %s\n", time.Since(t0).Milliseconds(), peek.Method)
		}

		// Check for cacheable methods
		if !noCache {
			var rpcReq struct {
				ID     json.RawMessage `json:"id,omitempty"`
				Method string          `json:"method"`
			}
			if json.Unmarshal([]byte(line), &rpcReq) == nil && rpcReq.ID != nil {
				idStr := string(rpcReq.ID)
				info := requestInfo{method: rpcReq.Method}

				var cachedResult json.RawMessage
				if cache != nil {
					switch rpcReq.Method {
					case "initialize":
						cachedResult = cache.Initialize
					case "tools/list":
						cachedResult = cache.ToolsList
					}
				}

				if cachedResult != nil {
					info.cached = true

					// Respond immediately from cache
					type rpcResponse struct {
						JSONRPC string          `json:"jsonrpc"`
						ID      json.RawMessage `json:"id"`
						Result  json.RawMessage `json:"result"`
					}
					out, _ := json.Marshal(rpcResponse{
						JSONRPC: "2.0",
						ID:      rpcReq.ID,
						Result:  cachedResult,
					})
					outStr := string(out)
					if len(stripCaps) > 0 {
						outStr = maybeStripCapabilities(outStr, stripCaps)
					}
					fmt.Fprintln(os.Stdout, outStr)
					if debug {
						fmt.Fprintf(os.Stderr, "[mcp-sse] +%dms cache-reply %s\n", time.Since(t0).Milliseconds(), rpcReq.Method)
					}
				}

				requests.Store(idStr, info)
			}
		}

		// Always forward to real server
		select {
		case <-endpointReady:
			postMessage(line)
		default:
			pendingMu.Lock()
			pending = append(pending, line)
			pendingMu.Unlock()
		}
	}
}

// maybeStripCapabilities removes specified capabilities from an initialize response.
func maybeStripCapabilities(data string, caps map[string]bool) string {
	var msg struct {
		Result *struct {
			Capabilities map[string]json.RawMessage `json:"capabilities,omitempty"`
		} `json:"result,omitempty"`
	}

	if err := json.Unmarshal([]byte(data), &msg); err != nil || msg.Result == nil || msg.Result.Capabilities == nil {
		return data
	}

	changed := false
	for cap := range caps {
		if _, ok := msg.Result.Capabilities[cap]; ok {
			delete(msg.Result.Capabilities, cap)
			changed = true
		}
	}

	if !changed {
		return data
	}

	// Re-serialize the full message preserving all other fields
	var full map[string]json.RawMessage
	json.Unmarshal([]byte(data), &full)

	var result map[string]json.RawMessage
	json.Unmarshal(full["result"], &result)

	capsBytes, _ := json.Marshal(msg.Result.Capabilities)
	result["capabilities"] = capsBytes

	resultBytes, _ := json.Marshal(result)
	full["result"] = resultBytes

	out, err := json.Marshal(full)
	if err != nil {
		return data
	}
	return string(out)
}
