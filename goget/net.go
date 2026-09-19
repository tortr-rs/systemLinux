package main

import (
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"time"
)

var httpClient = &http.Client{Timeout: 30 * time.Second}

// httpGet performs a GET request, following redirects, and returns the
// body and HTTP status. On a network-level failure (couldn't even reach
// the server), status is 0. extraHeaders is a list of "Name: value"
// strings, matching the C API's convention.
func httpGet(url string, extraHeaders []string) (string, int) {
	req, err := http.NewRequest(http.MethodGet, url, nil)
	if err != nil {
		fmt.Fprintf(os.Stderr, "goget: request to %s failed: %v\n", url, err)
		return "", 0
	}
	req.Header.Set("User-Agent", "goget/0.1")
	for _, h := range extraHeaders {
		if name, value, ok := strings.Cut(h, ": "); ok {
			req.Header.Set(name, value)
		}
	}

	resp, err := httpClient.Do(req)
	if err != nil {
		fmt.Fprintf(os.Stderr, "goget: request to %s failed: %v\n", url, err)
		return "", 0
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		fmt.Fprintf(os.Stderr, "goget: reading response from %s failed: %v\n", url, err)
		return "", resp.StatusCode
	}
	return string(body), resp.StatusCode
}

// progressWriter renders a colored, in-place download progress bar to
// stderr as bytes are written through it -- matching how curl/wget's own
// meters behave: only when stderr is a real terminal (so
// piped/redirected/logged output never fills with \r-overwritten junk),
// and only once the total size is known (some servers omit
// Content-Length, in which case it just stays silent).
type progressWriter struct {
	total    int64
	written  int64
	show     bool
	colored  bool
	finished bool
}

func (p *progressWriter) Write(b []byte) (int, error) {
	p.written += int64(len(b))
	if p.show && !p.finished {
		p.draw()
		if p.written >= p.total {
			fmt.Fprintln(os.Stderr)
			p.finished = true
		}
	}
	return len(b), nil
}

func (p *progressWriter) draw() {
	frac := float64(p.written) / float64(p.total)
	if frac > 1.0 {
		frac = 1.0
	}
	const width = 30
	filled := int(frac * width)

	fmt.Fprint(os.Stderr, "\r[")
	if p.colored {
		fmt.Fprint(os.Stderr, cCyan)
	}
	fmt.Fprint(os.Stderr, strings.Repeat("#", filled), strings.Repeat("-", width-filled))
	if p.colored {
		fmt.Fprint(os.Stderr, cReset)
	}
	fmt.Fprint(os.Stderr, "] ")
	if p.colored {
		fmt.Fprint(os.Stderr, cBold)
	}
	fmt.Fprintf(os.Stderr, "%3d%%", int(frac*100))
	if p.colored {
		fmt.Fprint(os.Stderr, cReset)
	}
}

// httpDownload streams url's body straight to destPath (never loading
// the whole file into memory), showing a progress bar as it goes.
// Returns an error on any network/status/filesystem failure.
func httpDownload(url, destPath string) error {
	req, err := http.NewRequest(http.MethodGet, url, nil)
	if err != nil {
		return err
	}
	req.Header.Set("User-Agent", "goget/0.1")

	client := &http.Client{Timeout: 5 * time.Minute}
	resp, err := client.Do(req)
	if err != nil {
		fmt.Fprintf(os.Stderr, "goget: download of %s failed: %v\n", url, err)
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		fmt.Fprintf(os.Stderr, "goget: download of %s failed: HTTP %d\n", url, resp.StatusCode)
		return fmt.Errorf("HTTP %d", resp.StatusCode)
	}

	f, err := os.Create(destPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "goget: %v\n", err)
		return err
	}
	defer f.Close()

	pw := &progressWriter{
		total:   resp.ContentLength,
		show:    isTerminal(os.Stderr) && resp.ContentLength > 0,
		colored: colorEnabledFor(os.Stderr),
	}
	if _, err := io.Copy(io.MultiWriter(f, pw), resp.Body); err != nil {
		fmt.Fprintf(os.Stderr, "goget: download of %s failed: %v\n", url, err)
		return err
	}
	return nil
}
