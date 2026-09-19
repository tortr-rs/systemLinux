#!/usr/bin/env python3
import curses
import curses.ascii
import fcntl
import json
import os
import pty
import re
import select
import struct
import subprocess
import sys
import termios
import threading
import time
import traceback
from pathlib import Path


OPTION_ALIASES = {
    "tabstop": "tabsize", "ts": "tabsize",
    "nu": "number", "numbers": "number",
    "rnu": "relativenumber",
}

CONFIG_FILES = [".evimrc.py", "evimrc.py", ".evimrc", "evimrc"]

class Editor:
    def __init__(self, filepath=None):
        self.filepath = filepath
        self.lines = [""]
        self.cx = 0
        self.cy = 0
        self.mode = "overlay"
        self.command = ""
        self.message = "EVim - normal mode"
        self.bindings = {}
        self.options = {
            "tabsize": 4,
            "number": False,
            "relativenumber": False,
            "show_command": True,
            "theme": "classic_blue",
            "indent_guides": False,
            "cursorline": False,
            "mouse": True,
            "wrap": False,
            "error_lens": True,
            "autosave": False,
            "autosave_delay": 5,
            "tabline": True,
            "bracket_highlight": True,
            "word_highlight": False,
            "statusline": True,
        }
        self.python_env = {"editor": self}
        self.start_hooks = []
        # Plugin system
        self.plugins = {}  # {name: {"name": str, "version": str, "setup": fn, "enabled": bool, ...}}
        self.event_hooks = {}  # {event_name: [callback, ...]}
        self.plugin_dirs = [
            Path.home() / ".config" / "evim" / "plugins",
            Path.cwd() / ".evim" / "plugins",
        ]
        self.autocommands = {}  # {event: [(pattern, callback), ...]}
        self.should_exit = False
        self.history = []
        self.clipboard = ""
        self.completion_index = 0
        self.completion_prefix = ""
        self.selection = None
        self.pending_normal = ""
        self.last_search = ""
        self.search_direction = 1
        self.show_welcome = True
        self.colors_initialized = False
        self.config_loading = True
        self.filetype = None
        self.syntax_language = None
        self.dirty = False
        self.cached_variables = set()
        self.buffers = {}  # NEW: For multi-file support {filepath: lines}
        self.buffer_order = []  # NEW: Track buffer open order
        self.current_buffer_idx = 0  # NEW: Current active buffer
        self.lsp_enabled = False
        self.lsp_diagnostics = []  # [(line, col, severity, message), ...]
        self.lsp_process = None
        self.lsp_request_id = 0
        self.lsp_responses = {}  # {id: response}
        self.lsp_capabilities = {}
        self.lsp_initialized = False
        self.lsp_lock = threading.Lock()
        self.lsp_hover_text = None
        self.lsp_completions = []  # [(label, detail), ...]
        self.lsp_completion_active = False
        self.lsp_completion_idx = 0
        self.lsp_server_cmd = None  # e.g. ['pyright-langserver', '--stdio']
        self.redo_stack = []  # For redo functionality
        self.scroll_top = 0  # Viewport top line
        self.scroll_left = 0  # Horizontal scroll offset
        # Dot repeat
        self.last_edit = None  # (action_name, args) for . repeat
        self.recording_edit = False
        self.edit_keys = []  # Keys captured during an edit for dot repeat
        # Macros
        self.macro_recording = None  # Register name currently recording, or None
        self.macro_keys = []  # Keys captured during macro recording
        self.macros = {}  # {register: [keys]}
        self.macro_playing = False
        # Marks
        self.marks = {}  # {char: (cy, cx)}
        # Registers
        self.registers = {}  # {char: text}  ('"' is default)
        self.pending_register = None  # Set by " key
        # Jump list
        self.jumplist = []  # [(cy, cx), ...]
        self.jumplist_pos = -1
        # Split panes
        self.splits = []  # List of pane dicts
        self.active_split = 0
        # Git gutter
        self.git_diff_lines = {}  # {lineno: 'added'|'modified'|'deleted'}
        # Persistent undo
        self.undo_file = None
        # Terminal panel
        self.term_visible = False
        self.term_fd = None
        self.term_pid = None
        self.term_lines = [""]  # scrollback buffer
        self.term_scroll = 0  # scroll offset within terminal output
        self.term_col = 0  # cursor column within current line (for \r handling)
        # Precompiled ANSI escape regex for terminal output stripping
        self._ansi_re = re.compile(
            r'\x1b\[[0-9;]*[a-zA-Z]'
            r'|\x1b\][^\x07]*\x07'
            r'|\x1b[()][AB012]'
            r'|\x1b\[\?[0-9;]*[a-zA-Z]'
        )
        # File explorer
        self.explorer_visible = False
        self.explorer_width = 25
        self.explorer_entries = []  # [(depth, name, fullpath, is_dir, expanded), ...]
        self.explorer_cursor = 0  # selected entry index
        self.explorer_scroll = 0  # scroll offset
        self.explorer_expanded = set()  # expanded directory paths
        self.explorer_cwd = str(Path.cwd())
        self._explorer_last_click = -1
        self._explorer_click_time = 0
        # Minimap
        self.minimap_visible = False
        self.minimap_width = 20
        # Menu system
        self.menu_visible = False
        self.menu_cursor = 0
        self._autosave_counter = 0
        self._bracket_match_pos = None
        self._color_depth = 8
        self._word_hl_positions = []  # [(y, x_start, x_end), ...]
        # Mouse state
        self._last_click_time = 0
        self._last_click_pos = (-1, -1)
        self._mouse_dragging = False
        self._triple_click_time = 0
        # Kill ring (multi-clipboard)
        self.kill_ring = []
        self.kill_ring_max = 30
        self.kill_ring_idx = 0
        # Incremental search
        self._isearch_active = False
        self._isearch_matches = []
        self._isearch_idx = 0
        self._isearch_origin = (0, 0)
        # Code folding
        self.folds = {}
        # Right-click context menu
        self._ctx_menu_visible = False
        self._ctx_menu_items = []
        self._ctx_menu_x = 0
        self._ctx_menu_y = 0
        self._ctx_menu_cursor = 0
        # Command palette
        self._palette_visible = False
        self._palette_query = ""
        self._palette_items = []
        self._palette_filtered = []
        self._palette_cursor = 0
        # Recent files
        self.recent_files = []
        self.recent_files_max = 25
        self._recent_file_path = Path.home() / ".config" / "evim" / "recent_files.json"
        # Project grep results
        self._grep_results = []
        self._grep_cursor = 0
        self._grep_visible = False
        # Symbol outline
        self._outline_visible = False
        self._outline_items = []
        self._outline_cursor = 0
        # Multi-cursor
        self.cursors = []  # [(cy, cx), ...] — extra cursors beyond the primary
        # Visual block mode
        self.selection_type = "char"   # "char" | "line" | "block"
        # Splits
        self.splits = []        # [{"filepath": str, "lines": list, "cy": int, "cx": int,
                                #   "scroll_top": int, "scroll_left": int, "direction": "h"|"v"}, ...]
        self.active_split = 0   # which split is focused (0 = main editor)
        # LSP extras
        self.lsp_inlay_hints = {}     # {line_no: [(col, label), ...]}
        self.lsp_action_items = []    # [(title, command, args), ...]
        self._diag_panel_visible = False
        self._diag_panel_cursor = 0
        # Session
        self._session_path = Path.home() / ".config" / "evim" / "session.json"
        # File watcher
        self._file_mtimes = {}   # {filepath: mtime}
        self._watcher_thread = None
        # Breadcrumbs
        self._breadcrumb = ""    # e.g. "MyClass > my_method"
        # Git
        self._git_status_lines = []
        self._git_status_visible = False
        self._git_status_cursor = 0
        # Surround pending
        self._surround_pending = None
        self._load_recent_files()
        self.read_file()
        if self.filepath:
            self.buffers[self.filepath] = self.lines[:]
            self.buffer_order = [self.filepath]
            self.current_buffer_idx = 0
        else:
            # Unnamed buffer — usable without a file path
            self.buffers["[No Name]"] = self.lines[:]
            self.buffer_order = ["[No Name]"]
            self.current_buffer_idx = 0
            self.message = "EVim - [No Name] (use :w <filename> to save)"
        self.load_config()
        self.config_loading = False
        # Start file watcher background thread
        self._start_file_watcher()
        # Auto-restore session if no file was specified
        if not self.filepath:
            self._session_restore_silent()

    def read_file(self):
        if not self.filepath:
            self.filetype = None
            self.syntax_language = None
            self.dirty = False
            return
        path = Path(self.filepath)
        self.filetype = path.suffix.lower()
        if path.exists():
            text = path.read_text(encoding="utf-8", errors="replace")
            self.lines = text.splitlines() or [""]
        else:
            self.lines = [""]
        self.detect_syntax()
        self.dirty = False

    def write_file(self):
        if not self.filepath:
            self.message = "No filename. Use :w <name> to save."
            return
        self.emit("before_save", filepath=self.filepath)
        try:
            data = "\n".join(self.lines) + ("\n" if self.lines else "")
            Path(self.filepath).write_text(data, encoding="utf-8")
            self.message = f"Saved {self.filepath}"
            self.dirty = False
            try:
                self.update_git_gutter()
            except Exception:
                pass
            self.emit("after_save", filepath=self.filepath)
        except Exception as exc:
            self.message = f"Save failed: {exc}"

    def do_completion(self):
        line = self.lines[self.cy]
        if self.cx == 0 or not self.syntax_language:
            self.snapshot()
            self.insert_char('\t')
            return
        word_start = self.cx
        while word_start > 0 and (line[word_start-1].isalnum() or line[word_start-1] == '_'):
            word_start -= 1
        prefix = line[word_start:self.cx]
        if not prefix or len(prefix) < 2:
            self.snapshot()
            self.insert_char('\t')
            return
        if prefix != self.completion_prefix:
            self.completion_index = 0
            self.completion_prefix = prefix
        candidates = []
        if prefix in self.snippets:
            candidates = [self.snippets[prefix]]
        else:
            keywords = set(self._cached_keywords)
            if not self.cached_variables:
                for l in self.lines:
                    words = re.findall(r'\b[a-zA-Z_]\w*\b', l)
                    self.cached_variables.update(words)
                self.cached_variables -= keywords
            variables = list(self.cached_variables)
            candidates = list(dict.fromkeys([k for k in list(keywords) + variables if k.startswith(prefix)]))
        if candidates:
            completion = candidates[self.completion_index % len(candidates)]
            self.completion_index += 1
            # Handle multi-line snippets
            if '\n' in completion:
                lines = completion.split('\n')
                # Insert first line at current position
                self.lines[self.cy] = line[:word_start] + lines[0] + line[self.cx:]
                self.cx = word_start + len(lines[0])
                # Insert remaining lines
                for i, l in enumerate(lines[1:], 1):
                    self.lines.insert(self.cy + i, l)
                # Move cursor to first placeholder or end
                if '|' in lines[0]:
                    pos = lines[0].find('|')
                    self.cx = word_start + pos
                    self.lines[self.cy] = self.lines[self.cy].replace('|', '')
                else:
                    self.cy += len(lines) - 1
                    self.cx = len(lines[-1])
            else:
                self.lines[self.cy] = line[:word_start] + completion + line[self.cx:]
                self.cx = word_start + len(completion)
            self.mark_dirty()
        else:
            self.snapshot()
            self.insert_char('\t')

    def run_mapped_action(self, action):
        cmd = action.strip()
        if cmd.endswith("<CR>"):
            cmd = cmd[:-4].strip()
        if cmd.startswith(":"):
            cmd = cmd[1:]
        self.run_ex(cmd)

    def load_config(self):
        selected = None
        app_dir = Path(__file__).resolve().parent
        search_paths = [Path.cwd() / name for name in CONFIG_FILES]
        search_paths.extend(app_dir / name for name in CONFIG_FILES)
        search_paths.append(Path.home() / ".evimrc.py")
        search_paths.append(Path.home() / ".evimrc")
        for candidate in search_paths:
            if candidate.exists():
                selected = candidate
                break
        if not selected:
            return
        content = selected.read_text(encoding="utf-8")
        old_loading = self.config_loading
        self.config_loading = True
        try:
            exec(compile(content, str(selected), "exec"), {"editor": self, "__builtins__": __builtins__})
        except Exception as exc:
            self.message = f"Config error: {exc}"
        finally:
            self.config_loading = old_loading
        self.message = f"Loaded {selected.name}"

    def init_colors(self):
        try:
            curses.start_color()
            curses.use_default_colors()
        except curses.error:
            # Not in a curses screen yet; keep config value and apply later.
            self.colors_initialized = False
            return
        theme = self.options.get("theme", "classic_blue")
        # (fg, bg, attr) for each syntax element
        B = curses.A_BOLD
        N = 0
        BLK = curses.COLOR_BLACK
        RED = curses.COLOR_RED
        GRN = curses.COLOR_GREEN
        YEL = curses.COLOR_YELLOW
        BLU = curses.COLOR_BLUE
        MAG = curses.COLOR_MAGENTA
        CYN = curses.COLOR_CYAN
        WHT = curses.COLOR_WHITE
        D = -1  # default bg
        # Each theme: (keyword, type, comment, string, number, preproc,
        #              text_fg, text_bg, lineno_fg, lineno_bg,
        #              status_fg, status_bg, cmdline_fg, cmdline_bg)
        THEMES = {
            "classic_blue":     ((BLU,BLK,B),  (YEL,BLK,B),  (CYN,BLK,N),  (GRN,BLK,N),  (MAG,BLK,N),  (RED,BLK,B),   WHT,BLK, CYN,BLK, WHT,BLU, WHT,BLK),
            "neon_nights":      ((MAG,BLK,B),  (CYN,BLK,B),  (GRN,BLK,N),  (YEL,BLK,N),  (WHT,BLK,B),  (RED,BLK,B),   WHT,BLK, MAG,BLK, BLK,MAG, MAG,BLK),
            "desert_storm":     ((YEL,BLK,B),  (RED,BLK,N),  (GRN,BLK,N),  (CYN,BLK,N),  (MAG,BLK,N),  (RED,BLK,B),   YEL,BLK, RED,BLK, BLK,YEL, YEL,BLK),
            "sunny_meadow":     ((GRN,BLK,B),  (YEL,BLK,B),  (WHT,BLK,N),  (CYN,BLK,N),  (MAG,BLK,N),  (RED,BLK,N),   GRN,BLK, YEL,BLK, BLK,GRN, GRN,BLK),
            "vampire_castle":   ((RED,BLK,B),  (MAG,BLK,B),  (WHT,BLK,N),  (GRN,BLK,N),  (CYN,BLK,N),  (YEL,BLK,N),   RED,BLK, MAG,BLK, WHT,RED, RED,BLK),
            "arctic_aurora":    ((CYN,BLK,B),  (GRN,BLK,B),  (WHT,BLK,N),  (MAG,BLK,N),  (YEL,BLK,N),  (BLU,BLK,B),   CYN,BLK, BLU,BLK, BLK,CYN, CYN,BLK),
            "forest_grove":     ((GRN,BLK,B),  (CYN,BLK,N),  (YEL,BLK,N),  (RED,BLK,N),  (MAG,BLK,N),  (BLU,BLK,B),   GRN,BLK, GRN,BLK, WHT,GRN, GRN,BLK),
            "golden_wheat":     ((YEL,BLK,B),  (WHT,BLK,B),  (GRN,BLK,N),  (CYN,BLK,N),  (RED,BLK,N),  (MAG,BLK,N),   YEL,BLK, YEL,BLK, BLK,YEL, YEL,BLK),
            "midnight_sky":     ((BLU,BLK,B),  (CYN,BLK,B),  (WHT,BLK,N),  (MAG,BLK,N),  (GRN,BLK,N),  (RED,BLK,B),   BLU,BLK, BLU,BLK, CYN,BLU, BLU,BLK),
            "cloudy_day":       ((BLU,WHT,N),  (BLK,WHT,B),  (GRN,WHT,N),  (RED,WHT,N),  (MAG,WHT,N),  (CYN,WHT,N),   BLK,WHT, BLU,WHT, BLK,WHT, BLU,WHT),
            "city_lights":      ((CYN,BLK,B),  (YEL,BLK,B),  (WHT,BLK,N),  (GRN,BLK,N),  (MAG,BLK,N),  (RED,BLK,N),   CYN,BLK, WHT,BLK, BLK,CYN, CYN,BLK),
            "creamy_latte":     ((MAG,WHT,B),  (BLU,WHT,B),  (GRN,WHT,N),  (RED,WHT,N),  (CYN,WHT,N),  (MAG,WHT,N),   BLK,WHT, MAG,WHT, BLK,WHT, MAG,WHT),
            "deep_space":       ((BLU,BLK,B),  (MAG,BLK,B),  (CYN,BLK,N),  (GRN,BLK,N),  (YEL,BLK,N),  (RED,BLK,B),   WHT,BLK, BLU,BLK, WHT,BLK, BLU,BLK),
            "fresh_breeze":     ((CYN,WHT,N),  (GRN,WHT,B),  (BLK,WHT,N),  (RED,WHT,N),  (BLU,WHT,N),  (MAG,WHT,N),   BLK,WHT, CYN,WHT, BLK,CYN, CYN,WHT),
            "matrix_code":      ((GRN,BLK,B),  (GRN,BLK,B),  (GRN,BLK,N),  (GRN,BLK,N),  (GRN,BLK,N),  (GRN,BLK,B),   GRN,BLK, GRN,BLK, GRN,BLK, GRN,BLK),
            "ocean_blue":       ((CYN,BLU,B),  (WHT,BLU,B),  (WHT,BLU,N),  (YEL,BLU,N),  (GRN,BLU,N),  (RED,BLU,B),   WHT,BLU, CYN,BLU, WHT,BLU, CYN,BLU),
            "fire_red":         ((RED,BLK,B),  (YEL,BLK,B),  (WHT,BLK,N),  (GRN,BLK,N),  (CYN,BLK,N),  (MAG,BLK,B),   RED,BLK, YEL,BLK, YEL,RED, RED,BLK),
            "forest_green":     ((GRN,BLK,B),  (YEL,BLK,B),  (CYN,BLK,N),  (RED,BLK,N),  (MAG,BLK,N),  (BLU,BLK,B),   GRN,BLK, GRN,BLK, BLK,GRN, GRN,BLK),
            "purple_haze":      ((MAG,BLK,B),  (BLU,BLK,B),  (CYN,BLK,N),  (GRN,BLK,N),  (RED,BLK,N),  (YEL,BLK,B),   MAG,BLK, MAG,BLK, WHT,MAG, MAG,BLK),
            "sunset_orange":    ((YEL,BLK,B),  (RED,BLK,B),  (CYN,BLK,N),  (MAG,BLK,N),  (GRN,BLK,N),  (BLU,BLK,B),   YEL,BLK, RED,BLK, BLK,YEL, YEL,BLK),
            "arctic_white":     ((BLK,WHT,B),  (BLU,WHT,B),  (GRN,WHT,N),  (RED,WHT,N),  (MAG,WHT,N),  (CYN,WHT,B),   BLK,WHT, BLU,WHT, BLK,WHT, BLU,WHT),
            "midnight_purple":  ((MAG,BLK,B),  (CYN,BLK,B),  (YEL,BLK,N),  (GRN,BLK,N),  (WHT,BLK,B),  (RED,BLK,B),   MAG,BLK, CYN,BLK, CYN,MAG, MAG,BLK),
            "desert_gold":      ((YEL,BLK,B),  (RED,BLK,N),  (GRN,BLK,N),  (CYN,BLK,N),  (WHT,BLK,N),  (MAG,BLK,B),   YEL,BLK, YEL,BLK, BLK,YEL, YEL,BLK),
            "cyber_pink":       ((MAG,BLK,B),  (CYN,BLK,B),  (GRN,BLK,N),  (YEL,BLK,N),  (WHT,BLK,B),  (RED,BLK,B),   MAG,BLK, MAG,BLK, BLK,MAG, MAG,BLK),
        }
        t = THEMES.get(theme, THEMES["classic_blue"])
        kw, ty, co, st, nu, pp = t[0], t[1], t[2], t[3], t[4], t[5]
        txt_fg, txt_bg = t[6], t[7]
        ln_fg, ln_bg = t[8], t[9]
        sfg, sbg = t[10], t[11]
        cmd_fg, cmd_bg = t[12], t[13]
        curses.init_pair(1, kw[0], kw[1])
        curses.init_pair(2, co[0], co[1])
        curses.init_pair(3, st[0], st[1])
        curses.init_pair(4, nu[0], nu[1])
        curses.init_pair(5, ty[0], ty[1])
        curses.init_pair(6, pp[0], pp[1])
        curses.init_pair(7, sfg, sbg)
        curses.init_pair(8, txt_fg, txt_bg)
        curses.init_pair(9, ln_fg, ln_bg)
        curses.init_pair(10, cmd_fg, cmd_bg)
        self.color_keyword = curses.color_pair(1) | kw[2]
        self.color_type = curses.color_pair(5) | ty[2]
        self.color_comment = curses.color_pair(2) | co[2]
        self.color_string = curses.color_pair(3) | st[2]
        self.color_number = curses.color_pair(4) | nu[2]
        self.color_preprocessor = curses.color_pair(6) | pp[2]
        self.color_status = curses.color_pair(7) | curses.A_BOLD
        self.color_default = curses.color_pair(8)
        self.color_lineno = curses.color_pair(9)
        self.color_cmdline = curses.color_pair(10)
        self.color_bg = curses.color_pair(8)
        # Detect terminal color capabilities
        self._color_depth = curses.COLORS if hasattr(curses, 'COLORS') else 8
        # Error lens colors (inline diagnostics)
        curses.init_pair(11, RED, BLK)    # error
        curses.init_pair(12, YEL, BLK)    # warning
        curses.init_pair(13, CYN, BLK)    # info/hint
        # Tab bar colors
        curses.init_pair(14, WHT, BLU)    # active tab
        curses.init_pair(15, WHT, BLK)    # inactive tab
        # Menu colors
        curses.init_pair(16, BLK, CYN)    # menu highlight
        curses.init_pair(17, WHT, BLU)    # menu header
        # Bracket match
        curses.init_pair(18, GRN, BLK)    # matching bracket
        # Word highlight
        curses.init_pair(19, BLK, YEL)    # word under cursor hl
        self.color_error_lens = curses.color_pair(11) | curses.A_BOLD
        self.color_warn_lens = curses.color_pair(12)
        self.color_info_lens = curses.color_pair(13)
        self.color_tab_active = curses.color_pair(14) | curses.A_BOLD
        self.color_tab_inactive = curses.color_pair(15)
        self.color_menu_hl = curses.color_pair(16) | curses.A_BOLD
        self.color_menu_header = curses.color_pair(17) | curses.A_BOLD
        self.color_bracket_match = curses.color_pair(18) | curses.A_BOLD | curses.A_UNDERLINE
        self.color_word_hl = curses.color_pair(19)
        self.colors_initialized = True

    def detect_syntax(self):
        extension_map = {
            ".c": "c", ".h": "c",
            ".cpp": "cpp", ".cc": "cpp", ".cxx": "cpp",
            ".hpp": "cpp", ".hh": "cpp", ".hxx": "cpp",
            ".cs": "csharp", ".rs": "rust", ".py": "python", ".lua": "lua",
            ".pas": "pascal", ".pp": "pascal", ".pascal": "pascal",
            ".f": "fortran", ".for": "fortran", ".f90": "fortran",
            ".f95": "fortran", ".f03": "fortran", ".f77": "fortran",
            ".evimrc": "evimlang",
            ".js": "javascript", ".jsx": "javascript", ".mjs": "javascript",
            ".ts": "typescript", ".tsx": "typescript",
            ".java": "java", ".go": "go",
            ".rb": "ruby", ".php": "php",
            ".pl": "perl", ".pm": "perl",
            ".swift": "swift",
            ".kt": "kotlin", ".kts": "kotlin",
            ".scala": "scala", ".sc": "scala",
            ".sh": "shell", ".bash": "shell", ".zsh": "shell",
            ".asm": "assembly", ".s": "assembly", ".nasm": "assembly", ".inc": "assembly",
            ".r": "r", ".R": "r",
            ".zig": "zig",
            ".nim": "nim",
            ".dart": "dart",
            ".ex": "elixir", ".exs": "elixir",
            ".erl": "erlang", ".hrl": "erlang",
            ".hs": "haskell", ".lhs": "haskell",
            ".ml": "ocaml", ".mli": "ocaml",
            ".clj": "clojure", ".cljs": "clojure", ".cljc": "clojure",
            ".lisp": "lisp", ".cl": "lisp", ".el": "lisp",
            ".vue": "vue",
            ".svelte": "svelte",
            ".yaml": "yaml", ".yml": "yaml",
            ".toml": "toml",
            ".json": "json",
            ".xml": "xml", ".xsl": "xml", ".xsd": "xml",
            ".html": "html", ".htm": "html",
            ".css": "css", ".scss": "scss", ".sass": "sass", ".less": "less",
            ".sql": "sql",
            ".md": "markdown", ".markdown": "markdown",
            ".cmake": "cmake",
            ".dockerfile": "dockerfile",
            ".proto": "protobuf",
            ".v": "v", ".vsh": "v",
            ".d": "dlang",
            ".m": "objectivec", ".mm": "objectivec",
            ".jl": "julia",
            ".ps1": "powershell", ".psm1": "powershell",
            ".tf": "terraform", ".hcl": "terraform",
            ".sol": "solidity",
            ".groovy": "groovy", ".gradle": "groovy",
        }
        self.syntax_language = extension_map.get(self.filetype, None)
        self.snippets = {}
        self.cached_variables.clear()
        if self.syntax_language == "python":
            self.snippets = {
                "if": "if :",
                "for": "for  in :",
                "def": "def ():",
                "class": "class :",
                "try": "try:\n\t\nexcept :",
            }
        elif self.syntax_language in ("c", "cpp", "csharp"):
            self.snippets = {
                "if": "if () {}",
                "for": "for (;;) {}",
                "while": "while () {}",
                "switch": "switch () {\n\tcase :\n\t\tbreak;\n}",
                "class": "class  {\n\t\n};",
                "struct": "struct  {\n\t\n};",
            }
        elif self.syntax_language == "rust":
            self.snippets = {
                "fn": "fn () {}",
                "if": "if  {}",
                "for": "for  in  {}",
                "struct": "struct  {\n\t\n}",
                "impl": "impl  {\n\t\n}",
            }
        elif self.syntax_language == "lua":
            self.snippets = {
                "if": "if  then\n\t\nend",
                "for": "for  do\n\t\nend",
                "function": "function ()\n\t\nend",
                "while": "while  do\n\t\nend",
            }
        elif self.syntax_language in ("java", "javascript", "typescript", "kotlin", "scala"):
            self.snippets = {
                "if": "if () {}", "for": "for (;;) {}",
                "while": "while () {}", "class": "class  {\n\t\n}",
            }
        elif self.syntax_language == "go":
            self.snippets = {
                "if": "if  {}", "for": "for  {}",
                "func": "func () {\n\t\n}", "struct": "type  struct {\n\t\n}",
            }
        elif self.syntax_language == "ruby":
            self.snippets = {
                "if": "if \n\t\nend", "def": "def \n\t\nend",
                "class": "class \n\t\nend",
            }
        elif self.syntax_language == "swift":
            self.snippets = {
                "if": "if  {}", "for": "for  in  {}",
                "func": "func () {\n\t\n}", "guard": "guard  else {\n\treturn\n}",
            }
        elif self.syntax_language == "shell":
            self.snippets = {
                "if": "if [[ ]]; then\n\t\nfi",
                "for": "for  in ; do\n\t\ndone",
                "while": "while [[ ]]; do\n\t\ndone",
                "function": "function () {\n\t\n}",
            }
        elif self.syntax_language == "php":
            self.snippets = {
                "if": "if () {}", "for": "for (;;) {}",
                "while": "while () {}", "function": "function () {\n\t\n}",
                "class": "class  {\n\t\n}",
            }
        # Add more as needed
        # Cache keyword and type sets for syntax highlighting performance
        self._cached_keywords = set(self.get_keyword_sets(self.syntax_language)) if self.syntax_language else set()
        self._cached_types = set(self.get_type_words(self.syntax_language)) if self.syntax_language else set()

    def get_keyword_sets(self, lang):
        default = {
            "if", "else", "for", "while", "return", "break", "continue",
            "switch", "case", "default", "do", "struct", "union", "enum",
            "const", "static", "volatile", "extern", "goto", "sizeof",
            "namespace", "using", "new", "delete", "try", "catch", "finally",
            "class", "public", "private", "protected", "override", "virtual",
            "template", "typename", "this", "throw", "operator", "inline",
            "auto", "constexpr", "decltype", "typedef", "friend", "mutable",
            "namespace", "using", "nullptr", "constexpr", "noexcept", "offsetof",
        }
        python = {
            "def", "class", "import", "from", "as", "if", "elif", "else",
            "for", "while", "return", "break", "continue", "try", "except",
            "finally", "with", "lambda", "yield", "global", "nonlocal",
            "assert", "pass", "raise", "del", "True", "False", "None",
            "async", "await", "in", "is", "and", "or", "not",
        }
        lua = {
            "and", "break", "do", "else", "elseif", "end", "false", "for",
            "function", "if", "in", "local", "nil", "not", "or", "repeat",
            "return", "then", "true", "until", "while", "goto",
        }
        pascal = {
            "begin", "end", "var", "const", "type", "record", "procedure",
            "function", "program", "if", "then", "else", "for", "to", "downto",
            "while", "repeat", "until", "case", "of", "uses", "unit", "interface",
            "implementation", "with", "nil", "in", "out", "div", "mod",
            "packed", "set", "array", "string", "object", "class", "constructor",
            "destructor", "inline", "override", "virtual", "absolute", "reintroduce",
        }
        fortran = {
            "program", "end", "function", "subroutine", "integer", "real",
            "double", "complex", "logical", "character", "if", "then", "else",
            "elseif", "do", "continue", "goto", "stop", "return", "call",
            "module", "use", "contains", "interface", "enddo", "endif",
            "implicit", "none", "parameter", "real", "doubleprecision", "allocate",
            "deallocate", "type", "kind", "dimension", "intent",
        }
        rust = {
            "fn", "let", "mut", "pub", "crate", "mod", "use", "impl", "trait",
            "struct", "enum", "match", "if", "else", "loop", "while", "for",
            "in", "as", "const", "static", "ref", "return", "break", "continue",
            "unsafe", "async", "await", "dyn", "where", "move", "type", "self",
            "super", "extern", "crate", "macro_rules", "impl", "trait", "override",
        }
        csharp = default | {"namespace", "using", "async", "await", "var", "new", "get", "set", "sealed", "readonly", "event", "delegate", "base", "override", "partial", "virtual", "abstract", "checked", "unchecked", "fixed", "unsafe", "stackalloc"}
        cpp = default | {"nullptr", "template", "typename", "using", "static_cast", "dynamic_cast", "reinterpret_cast", "noexcept", "final", "decltype", "constexpr", "mutable", "friend", "export", "explicit", "alignas", "alignof", "thread_local"}
        c = default | {"inline", "restrict", "signed", "unsigned", "short", "long", "void", "char", "int", "float", "double", "bool", "wchar_t", "size_t", "ptrdiff_t"}
        rust_k = rust
        evimlang = {"set", "map", "python"}
        javascript = {
            "var", "let", "const", "function", "return", "if", "else", "for",
            "while", "do", "switch", "case", "default", "break", "continue",
            "new", "delete", "typeof", "instanceof", "in", "of", "this",
            "class", "extends", "super", "import", "export", "from", "as",
            "try", "catch", "finally", "throw", "async", "await", "yield",
            "void", "with", "debugger", "true", "false", "null", "undefined",
        }
        typescript = javascript | {
            "type", "interface", "enum", "namespace", "module", "declare",
            "abstract", "implements", "readonly", "keyof", "infer", "is",
            "asserts", "any", "never", "unknown",
        }
        java_k = {
            "abstract", "assert", "break", "case", "catch", "class", "const",
            "continue", "default", "do", "else", "enum", "extends", "final",
            "finally", "for", "goto", "if", "implements", "import",
            "instanceof", "interface", "native", "new", "package", "private",
            "protected", "public", "return", "static", "strictfp", "super",
            "switch", "synchronized", "this", "throw", "throws", "transient",
            "try", "void", "volatile", "while", "true", "false", "null",
        }
        go_k = {
            "break", "case", "chan", "const", "continue", "default", "defer",
            "else", "fallthrough", "for", "func", "go", "goto", "if",
            "import", "interface", "map", "package", "range", "return",
            "select", "struct", "switch", "type", "var", "true", "false",
            "nil", "iota",
        }
        ruby_k = {
            "def", "class", "module", "end", "if", "elsif", "else", "unless",
            "case", "when", "while", "until", "for", "do", "begin", "rescue",
            "ensure", "raise", "return", "yield", "next", "break", "redo",
            "retry", "in", "then", "self", "super", "nil", "true", "false",
            "and", "or", "not", "require", "include", "attr_reader",
            "attr_writer", "attr_accessor", "puts", "print", "lambda", "proc",
            "private", "public", "protected",
        }
        php_k = {
            "if", "else", "elseif", "while", "do", "for", "foreach", "as",
            "switch", "case", "default", "break", "continue", "return",
            "function", "class", "new", "try", "catch", "finally", "throw",
            "namespace", "use", "extends", "implements", "interface",
            "abstract", "public", "private", "protected", "static", "const",
            "var", "echo", "print", "isset", "unset", "empty", "array",
            "list", "global", "true", "false", "null", "yield", "match",
            "enum", "readonly", "fn",
        }
        perl_k = {
            "my", "our", "local", "sub", "if", "elsif", "else", "unless",
            "while", "until", "for", "foreach", "do", "return", "last",
            "next", "redo", "use", "require", "package", "BEGIN", "END",
            "die", "warn", "print", "say", "chomp", "push", "pop", "shift",
            "unshift", "defined", "undef", "eval", "grep", "map", "sort",
            "keys", "values", "exists", "delete", "bless", "ref",
        }
        swift_k = {
            "import", "class", "struct", "enum", "protocol", "extension",
            "func", "var", "let", "if", "else", "guard", "switch", "case",
            "default", "for", "in", "while", "repeat", "break", "continue",
            "return", "throw", "throws", "rethrows", "try", "catch", "do",
            "as", "is", "self", "Self", "super", "init", "deinit", "nil",
            "true", "false", "public", "private", "internal", "open",
            "fileprivate", "static", "override", "final", "lazy", "weak",
            "unowned", "mutating", "inout", "where", "async", "await",
        }
        kotlin_k = {
            "fun", "val", "var", "if", "else", "when", "for", "while", "do",
            "return", "break", "continue", "class", "object", "interface",
            "enum", "sealed", "data", "open", "abstract", "override",
            "private", "protected", "public", "internal", "companion",
            "init", "this", "super", "package", "import", "as", "is", "in",
            "try", "catch", "finally", "throw", "null", "true", "false",
            "it", "by", "lazy", "lateinit", "suspend", "inline", "typealias",
        }
        scala_k = {
            "def", "val", "var", "class", "object", "trait", "extends",
            "with", "import", "package", "if", "else", "match", "case",
            "for", "while", "do", "return", "yield", "throw", "try",
            "catch", "finally", "new", "this", "super", "override",
            "abstract", "final", "sealed", "private", "protected",
            "implicit", "lazy", "type", "true", "false", "null",
        }
        shell_k = {
            "if", "then", "else", "elif", "fi", "case", "esac", "for",
            "while", "until", "do", "done", "in", "function", "return",
            "exit", "break", "continue", "local", "export", "readonly",
            "declare", "typeset", "unset", "shift", "source", "eval",
            "exec", "trap", "set", "echo", "printf", "read", "test",
            "true", "false",
        }
        assembly_k = {
            "mov", "add", "sub", "mul", "div", "push", "pop", "call", "ret",
            "jmp", "je", "jne", "jz", "jnz", "jg", "jge", "jl", "jle",
            "ja", "jb", "jae", "jbe", "cmp", "test", "and", "or", "xor",
            "not", "shl", "shr", "sal", "sar", "rol", "ror", "lea", "nop",
            "int", "syscall", "hlt", "inc", "dec", "imul", "idiv", "neg",
            "movzx", "movsx", "cdq", "rep", "movs", "stos",
            "ldr", "str", "ldm", "stm", "bl", "bx", "blx", "svc",
            "li", "la", "lw", "sw", "lb", "sb", "beq", "bne", "addi",
            "jal", "jr", "lui", "auipc", "ecall",
            "section", "segment", "global", "extern", "db", "dw", "dd",
            "dq", "resb", "resw", "resd", "resq", "equ", "times", "org",
            "align", "bits", "include",
        }
        if lang == "python":
            return python
        if lang == "lua":
            return lua
        if lang == "pascal":
            return pascal
        if lang == "fortran":
            return fortran
        if lang == "rust":
            return rust_k
        if lang == "csharp":
            return csharp
        if lang == "cpp":
            return cpp
        if lang == "c":
            return c
        if lang == "evimlang":
            return evimlang
        if lang == "javascript":
            return javascript
        if lang == "typescript":
            return typescript
        if lang == "java":
            return java_k
        if lang == "go":
            return go_k
        if lang == "ruby":
            return ruby_k
        if lang == "php":
            return php_k
        if lang == "perl":
            return perl_k
        if lang == "swift":
            return swift_k
        if lang == "kotlin":
            return kotlin_k
        if lang == "scala":
            return scala_k
        if lang == "shell":
            return shell_k
        if lang == "assembly":
            return assembly_k
        # New languages - use C-like defaults with language-specific additions
        zig_k = {"fn", "pub", "const", "var", "comptime", "inline", "extern", "export", "try", "catch", "unreachable", "defer", "errdefer", "orelse", "if", "else", "while", "for", "switch", "break", "continue", "return", "struct", "enum", "union", "error", "test", "async", "await", "suspend", "resume", "threadlocal", "usingnamespace"}
        nim_k = {"proc", "func", "method", "var", "let", "const", "type", "object", "ref", "ptr", "import", "include", "from", "export", "template", "macro", "iterator", "converter", "when", "case", "of", "if", "elif", "else", "while", "for", "in", "block", "try", "except", "finally", "raise", "yield", "discard", "return", "result", "nil"}
        dart_k = {"abstract", "as", "assert", "async", "await", "break", "case", "catch", "class", "const", "continue", "covariant", "default", "deferred", "do", "dynamic", "else", "enum", "export", "extends", "extension", "external", "factory", "final", "finally", "for", "get", "if", "implements", "import", "in", "interface", "is", "late", "library", "mixin", "new", "null", "on", "operator", "part", "required", "rethrow", "return", "sealed", "set", "show", "static", "super", "switch", "sync", "this", "throw", "try", "typedef", "var", "void", "while", "with", "yield"}
        elixir_k = {"def", "defp", "defmodule", "defmacro", "defstruct", "defprotocol", "defimpl", "do", "end", "if", "else", "unless", "case", "cond", "when", "with", "fn", "raise", "rescue", "try", "catch", "after", "for", "in", "import", "use", "alias", "require", "and", "or", "not", "true", "false", "nil", "pipe", "send", "receive"}
        haskell_k = {"module", "where", "import", "qualified", "as", "hiding", "data", "type", "newtype", "class", "instance", "deriving", "if", "then", "else", "case", "of", "let", "in", "do", "where", "forall", "infixl", "infixr", "infix"}
        ocaml_k = {"let", "in", "if", "then", "else", "match", "with", "function", "fun", "rec", "and", "or", "not", "type", "module", "struct", "sig", "end", "val", "open", "include", "exception", "try", "raise", "begin", "for", "while", "do", "done", "to", "downto", "mutable", "ref"}
        clojure_k = {"def", "defn", "defmacro", "fn", "let", "loop", "recur", "if", "when", "cond", "case", "do", "try", "catch", "finally", "throw", "ns", "require", "import", "use", "in-ns", "refer", "atom", "deref", "swap!", "reset!", "assoc", "dissoc", "conj", "cons", "map", "filter", "reduce"}
        lisp_k = {"defun", "defvar", "defparameter", "defconstant", "defmacro", "lambda", "let", "let*", "setq", "setf", "if", "when", "unless", "cond", "case", "progn", "loop", "do", "dolist", "dotimes", "return", "nil", "t", "and", "or", "not", "car", "cdr", "cons", "list", "append", "funcall", "apply", "format"}
        julia_k = {"function", "end", "if", "elseif", "else", "for", "while", "try", "catch", "finally", "return", "break", "continue", "begin", "let", "local", "global", "const", "struct", "mutable", "abstract", "primitive", "type", "module", "import", "using", "export", "macro", "do", "in", "isa", "where"}
        r_k = {"function", "if", "else", "for", "while", "repeat", "in", "next", "break", "return", "library", "require", "source", "TRUE", "FALSE", "NULL", "NA", "Inf", "NaN"}
        sql_k = {"SELECT", "FROM", "WHERE", "INSERT", "INTO", "VALUES", "UPDATE", "SET", "DELETE", "CREATE", "TABLE", "ALTER", "DROP", "INDEX", "VIEW", "JOIN", "INNER", "LEFT", "RIGHT", "OUTER", "ON", "GROUP", "BY", "ORDER", "HAVING", "LIMIT", "OFFSET", "UNION", "AND", "OR", "NOT", "NULL", "AS", "DISTINCT", "COUNT", "SUM", "AVG", "MIN", "MAX", "LIKE", "IN", "BETWEEN", "EXISTS", "CASE", "WHEN", "THEN", "ELSE", "END", "PRIMARY", "KEY", "FOREIGN", "REFERENCES", "CONSTRAINT", "DEFAULT", "CHECK", "UNIQUE", "BEGIN", "COMMIT", "ROLLBACK", "TRANSACTION"}
        html_k = {"html", "head", "body", "div", "span", "p", "a", "img", "table", "tr", "td", "th", "form", "input", "button", "select", "option", "ul", "ol", "li", "h1", "h2", "h3", "h4", "h5", "h6", "script", "style", "link", "meta", "title", "section", "article", "nav", "header", "footer", "main", "aside"}
        css_k = {"color", "background", "margin", "padding", "border", "display", "position", "top", "left", "right", "bottom", "width", "height", "font", "text", "flex", "grid", "align", "justify", "overflow", "opacity", "transform", "transition", "animation", "z-index", "cursor", "visibility", "important"}
        yaml_k = {"true", "false", "null", "yes", "no", "on", "off"}
        solidity_k = {"pragma", "solidity", "contract", "interface", "library", "function", "modifier", "event", "emit", "mapping", "struct", "enum", "if", "else", "for", "while", "do", "break", "continue", "return", "require", "revert", "assert", "payable", "view", "pure", "external", "internal", "public", "private", "virtual", "override", "memory", "storage", "calldata"}
        terraform_k = {"resource", "data", "variable", "output", "locals", "module", "provider", "terraform", "required_providers", "backend", "for_each", "count", "depends_on", "lifecycle", "provisioner", "dynamic", "content"}
        dlang_k = {"module", "import", "class", "struct", "interface", "enum", "union", "void", "auto", "if", "else", "while", "for", "foreach", "do", "switch", "case", "default", "break", "continue", "return", "scope", "delegate", "function", "lazy", "template", "mixin", "alias", "typeof", "typeid", "is", "assert", "throw", "try", "catch", "finally", "immutable", "const", "shared", "pure", "nothrow", "override", "abstract", "final", "synchronized"}
        v_k = {"fn", "pub", "mut", "const", "struct", "enum", "union", "interface", "type", "import", "module", "if", "else", "for", "in", "match", "or", "and", "not", "return", "defer", "go", "spawn", "shared", "lock", "rlock", "unsafe", "assert", "none", "true", "false"}
        groovy_k = default | {"def", "as", "in", "trait", "with", "assert", "println"}
        powershell_k = {"function", "param", "begin", "process", "end", "if", "elseif", "else", "switch", "while", "for", "foreach", "do", "until", "try", "catch", "finally", "throw", "return", "break", "continue", "exit", "Write-Host", "Write-Output", "Get-Item", "Set-Item", "New-Object", "Import-Module"}
        if lang == "zig":
            return zig_k
        if lang == "nim":
            return nim_k
        if lang == "dart":
            return dart_k
        if lang == "elixir":
            return elixir_k
        if lang == "haskell":
            return haskell_k
        if lang == "ocaml":
            return ocaml_k
        if lang in ("clojure",):
            return clojure_k
        if lang == "lisp":
            return lisp_k
        if lang == "julia":
            return julia_k
        if lang == "r":
            return r_k
        if lang == "sql":
            return sql_k
        if lang in ("html", "xml", "vue", "svelte"):
            return html_k
        if lang in ("css", "scss", "sass", "less"):
            return css_k
        if lang in ("yaml", "toml", "json"):
            return yaml_k
        if lang == "solidity":
            return solidity_k
        if lang == "terraform":
            return terraform_k
        if lang == "dlang":
            return dlang_k
        if lang == "v":
            return v_k
        if lang == "groovy":
            return groovy_k
        if lang == "powershell":
            return powershell_k
        if lang == "erlang":
            return elixir_k
        if lang == "objectivec":
            return default
        if lang in ("markdown", "protobuf", "cmake", "dockerfile"):
            return default
        return default

    def get_type_words(self, lang):
        base_types = {"int", "float", "double", "char", "bool", "long", "short", "void", "wchar_t", "size_t", "ptrdiff_t", "auto"}
        pascal_types = {"integer", "real", "boolean", "string", "char", "text", "byte", "word", "longint", "qword"}
        fortran_types = {"integer", "real", "complex", "logical", "character", "doubleprecision"}
        python_types = {"int", "float", "bool", "str", "list", "dict", "set", "tuple", "None", "True", "False"}
        lua_types = {"nil", "table", "userdata", "function"}
        rust_types = {"i32", "i64", "u32", "u64", "usize", "isize", "f32", "f64", "String", "str", "bool", "char"}
        if lang == "pascal":
            return pascal_types
        if lang == "fortran":
            return fortran_types
        if lang == "python":
            return python_types
        if lang == "lua":
            return lua_types
        if lang == "rust":
            return rust_types
        javascript_types = {"Number", "String", "Boolean", "Object", "Array", "Function", "Symbol", "BigInt", "Map", "Set", "Promise", "Date", "RegExp", "Error"}
        typescript_types = javascript_types | {"string", "number", "boolean", "void", "any", "never", "unknown", "object", "symbol", "bigint", "undefined"}
        java_types = {"int", "long", "short", "byte", "float", "double", "char", "boolean", "void", "String", "Integer", "Long", "Float", "Double", "Boolean", "Object", "List", "Map", "Set"}
        go_types = {"int", "int8", "int16", "int32", "int64", "uint", "uint8", "uint16", "uint32", "uint64", "float32", "float64", "complex64", "complex128", "string", "bool", "byte", "rune", "error", "any"}
        ruby_types = {"String", "Integer", "Float", "Array", "Hash", "Symbol", "Regexp", "Range", "Proc", "IO", "File", "NilClass"}
        php_types = {"int", "float", "string", "bool", "array", "object", "callable", "void", "mixed", "never", "null", "self", "static", "iterable"}
        swift_types = {"Int", "Int8", "Int16", "Int32", "Int64", "UInt", "Float", "Double", "Bool", "String", "Character", "Array", "Dictionary", "Set", "Optional", "Any", "Void", "Never"}
        kotlin_types = {"Int", "Long", "Short", "Byte", "Float", "Double", "Boolean", "Char", "String", "Unit", "Nothing", "Any", "Array", "List", "Map", "Set", "Pair"}
        scala_types = {"Int", "Long", "Short", "Byte", "Float", "Double", "Boolean", "Char", "String", "Unit", "Nothing", "Any", "AnyRef", "List", "Map", "Set", "Option", "Vector", "Seq"}
        assembly_types = {
            "eax", "ebx", "ecx", "edx", "esi", "edi", "ebp", "esp",
            "rax", "rbx", "rcx", "rdx", "rsi", "rdi", "rbp", "rsp",
            "r8", "r9", "r10", "r11", "r12", "r13", "r14", "r15",
            "ax", "bx", "cx", "dx", "al", "bl", "cl", "dl",
            "sp", "lr", "pc", "xmm0", "xmm1", "xmm2", "xmm3",
        }
        if lang == "javascript":
            return javascript_types
        if lang == "typescript":
            return typescript_types
        if lang == "java":
            return java_types
        if lang == "go":
            return go_types
        if lang == "ruby":
            return ruby_types
        if lang == "php":
            return php_types
        if lang == "swift":
            return swift_types
        if lang == "kotlin":
            return kotlin_types
        if lang == "scala":
            return scala_types
        if lang == "assembly":
            return assembly_types
        if lang in ("perl", "shell"):
            return set()
        zig_types = {"u8", "u16", "u32", "u64", "u128", "i8", "i16", "i32", "i64", "i128", "f16", "f32", "f64", "f128", "usize", "isize", "bool", "void", "anytype", "noreturn", "type", "comptime_int", "comptime_float"}
        nim_types = {"int", "int8", "int16", "int32", "int64", "uint", "uint8", "uint16", "uint32", "uint64", "float", "float32", "float64", "bool", "char", "string", "seq", "array", "set", "tuple", "void", "auto", "any"}
        dart_types = {"int", "double", "num", "String", "bool", "List", "Map", "Set", "Future", "Stream", "Iterable", "dynamic", "void", "Object", "Null", "Never", "Function", "Type", "Symbol"}
        elixir_types = {"integer", "float", "atom", "string", "list", "tuple", "map", "pid", "port", "reference", "binary", "function", "boolean"}
        haskell_types = {"Int", "Integer", "Float", "Double", "Char", "String", "Bool", "IO", "Maybe", "Either", "Monad", "Functor", "Applicative", "Show", "Eq", "Ord", "Num"}
        ocaml_types = {"int", "float", "bool", "char", "string", "unit", "list", "array", "option", "ref", "exn", "bytes"}
        julia_types = {"Int", "Int8", "Int16", "Int32", "Int64", "UInt8", "UInt16", "UInt32", "UInt64", "Float16", "Float32", "Float64", "Bool", "Char", "String", "Array", "Dict", "Set", "Tuple", "Nothing", "Any", "Number", "Real", "Complex", "Vector", "Matrix"}
        r_types = {"numeric", "integer", "double", "complex", "character", "logical", "raw", "list", "vector", "matrix", "data.frame", "factor", "array"}
        dlang_types = {"int", "uint", "long", "ulong", "short", "ushort", "byte", "ubyte", "float", "double", "real", "bool", "char", "wchar", "dchar", "string", "wstring", "dstring", "size_t", "ptrdiff_t", "void"}
        v_types = {"int", "i8", "i16", "i64", "u8", "u16", "u32", "u64", "f32", "f64", "bool", "string", "rune", "byte", "voidptr", "any"}
        solidity_types = {"uint", "uint8", "uint16", "uint32", "uint64", "uint128", "uint256", "int256", "address", "bool", "string", "bytes", "bytes32", "mapping"}
        if lang == "zig":
            return zig_types
        if lang == "nim":
            return nim_types
        if lang == "dart":
            return dart_types
        if lang in ("elixir", "erlang"):
            return elixir_types
        if lang == "haskell":
            return haskell_types
        if lang == "ocaml":
            return ocaml_types
        if lang in ("clojure", "lisp"):
            return set()
        if lang == "julia":
            return julia_types
        if lang == "r":
            return r_types
        if lang == "dlang":
            return dlang_types
        if lang == "v":
            return v_types
        if lang == "solidity":
            return solidity_types
        if lang in ("sql", "html", "xml", "css", "scss", "sass", "less", "yaml", "toml", "json", "markdown", "vue", "svelte", "protobuf", "cmake", "dockerfile", "terraform", "groovy", "powershell", "objectivec"):
            return base_types
        return base_types

    def highlight_line(self, stdscr, y, line, prefix, width, cursor_col=None, x_offset=0):
        """Draw one line with syntax highlighting. Returns the x position after drawing."""
        x = x_offset
        if prefix:
            ln_attr = getattr(self, 'color_lineno', self.color_default)
            self.draw_segment(stdscr, y, x, prefix, ln_attr, cursor_col=None, base=0)
            x += len(prefix)
        content = line
        lang = self.syntax_language
        pos = 0
        while pos < len(content):
            if lang in ("c", "cpp", "csharp", "rust"):
                if content[pos:].lstrip().startswith("#") and content[:pos].strip() == "":
                    self.draw_segment(stdscr, y, x, content[pos:], self.color_preprocessor, cursor_col, base=pos)
                    x += len(content) - pos; break
                if content.startswith("//", pos):
                    self.draw_segment(stdscr, y, x, content[pos:], self.color_comment, cursor_col, base=pos)
                    x += len(content) - pos; break
                if content.startswith("/*", pos):
                    end = content.find("*/", pos + 2)
                    if end < 0:
                        end = len(content)
                    else:
                        end += 2
                    self.draw_segment(stdscr, y, x, content[pos:end], self.color_comment, cursor_col, base=pos)
                    x += end - pos
                    pos = end
                    continue
            elif lang in ("java", "go", "javascript", "typescript", "swift", "kotlin", "scala"):
                if content.startswith("//", pos):
                    self.draw_segment(stdscr, y, x, content[pos:], self.color_comment, cursor_col, base=pos)
                    x += len(content) - pos; break
                if content.startswith("/*", pos):
                    end = content.find("*/", pos + 2)
                    if end < 0:
                        end = len(content)
                    else:
                        end += 2
                    self.draw_segment(stdscr, y, x, content[pos:end], self.color_comment, cursor_col, base=pos)
                    x += end - pos
                    pos = end
                    continue
            elif lang == "python":
                if content.startswith("#", pos):
                    self.draw_segment(stdscr, y, x, content[pos:], self.color_comment, cursor_col, base=pos)
                    x += len(content) - pos; break
                if content.startswith("@", pos):
                    end = pos + 1
                    while end < len(content) and (content[end].isalnum() or content[end] in "_."):
                        end += 1
                    self.draw_segment(stdscr, y, x, content[pos:end], self.color_preprocessor, cursor_col, base=pos)
                    x += end - pos
                    pos = end
                    continue
            elif lang == "lua":
                if content.startswith("--", pos):
                    self.draw_segment(stdscr, y, x, content[pos:], self.color_comment, cursor_col, base=pos)
                    x += len(content) - pos; break
            elif lang == "pascal":
                if content.startswith("//", pos):
                    self.draw_segment(stdscr, y, x, content[pos:], self.color_comment, cursor_col, base=pos)
                    x += len(content) - pos; break
                if content.startswith("{", pos):
                    end = content.find("}", pos + 1)
                    if end < 0:
                        end = len(content)
                    else:
                        end += 1
                    self.draw_segment(stdscr, y, x, content[pos:end], self.color_comment, cursor_col, base=pos)
                    x += end - pos
                    pos = end
                    continue
                if content.startswith("(*", pos):
                    end = content.find("*)", pos + 2)
                    if end < 0:
                        end = len(content)
                    else:
                        end += 2
                    self.draw_segment(stdscr, y, x, content[pos:end], self.color_comment, cursor_col, base=pos)
                    x += end - pos
                    pos = end
                    continue
            elif lang == "fortran":
                if content.startswith("!", pos):
                    self.draw_segment(stdscr, y, x, content[pos:], self.color_comment, cursor_col, base=pos)
                    x += len(content) - pos; break
            elif lang in ("ruby", "shell", "perl"):
                if content.startswith("#", pos):
                    self.draw_segment(stdscr, y, x, content[pos:], self.color_comment, cursor_col, base=pos)
                    x += len(content) - pos; break
            elif lang == "php":
                if content.startswith("//", pos) or content.startswith("#", pos):
                    self.draw_segment(stdscr, y, x, content[pos:], self.color_comment, cursor_col, base=pos)
                    x += len(content) - pos; break
                if content.startswith("/*", pos):
                    end = content.find("*/", pos + 2)
                    if end < 0:
                        end = len(content)
                    else:
                        end += 2
                    self.draw_segment(stdscr, y, x, content[pos:end], self.color_comment, cursor_col, base=pos)
                    x += end - pos
                    pos = end
                    continue
            elif lang == "assembly":
                if content[pos] in (";", "#", "@"):
                    self.draw_segment(stdscr, y, x, content[pos:], self.color_comment, cursor_col, base=pos)
                    x += len(content) - pos; break
                if content.startswith("/*", pos):
                    end = content.find("*/", pos + 2)
                    if end < 0:
                        end = len(content)
                    else:
                        end += 2
                    self.draw_segment(stdscr, y, x, content[pos:end], self.color_comment, cursor_col, base=pos)
                    x += end - pos
                    pos = end
                    continue
                if content[pos] == ".":
                    end = pos + 1
                    while end < len(content) and (content[end].isalnum() or content[end] == "_"):
                        end += 1
                    self.draw_segment(stdscr, y, x, content[pos:end], self.color_preprocessor, cursor_col, base=pos)
                    x += end - pos
                    pos = end
                    continue
            elif lang == "evimlang":
                if content.startswith("\"", pos):
                    self.draw_segment(stdscr, y, x, content[pos:], self.color_comment, cursor_col, base=pos)
                    x += len(content) - pos; break
                if content[pos] in ('"', "'"):
                    delim = content[pos]
                    end = pos + 1
                    while end < len(content):
                        if content[end] == "\\" and end + 1 < len(content):
                            end += 2
                            continue
                        if content[end] == delim:
                            end += 1
                            break
                        end += 1
                    self.draw_segment(stdscr, y, x, content[pos:end], self.color_string, cursor_col, base=pos)
                    x += end - pos
                    pos = end
                    continue
            if content[pos] in ('"', "'"):
                delim = content[pos]
                end = pos + 1
                while end < len(content):
                    if content[end] == "\\" and end + 1 < len(content):
                        end += 2
                        continue
                    if content[end] == delim:
                        end += 1
                        break
                    end += 1
                self.draw_segment(stdscr, y, x, content[pos:end], self.color_string, cursor_col, base=pos)
                x += end - pos
                pos = end
                continue
            if content[pos].isdigit():
                start = pos
                if content.startswith("0x", pos) or content.startswith("0X", pos):
                    pos += 2
                    while pos < len(content) and (content[pos].isdigit() or content[pos].lower() in "abcdef"):
                        pos += 1
                else:
                    while pos < len(content) and (content[pos].isdigit() or content[pos] in ".eE+-"):
                        pos += 1
                self.draw_segment(stdscr, y, x, content[start:pos], self.color_number, cursor_col, base=start)
                x += pos - start
                continue
            if content[pos].isalpha() or content[pos] == "_":
                start = pos
                while pos < len(content) and (content[pos].isalnum() or content[pos] == "_"):
                    pos += 1
                token = content[start:pos]
                token_key = token if lang not in ("fortran", "pascal") else token.lower()
                attr = self.color_default
                if token_key in self._cached_keywords:
                    attr = self.color_keyword
                elif token_key in self._cached_types:
                    attr = self.color_type
                self.draw_segment(stdscr, y, x, token, attr, cursor_col, base=start)
                x += len(token)
                continue
            self.draw_segment(stdscr, y, x, content[pos], self.color_default, cursor_col, base=pos)
            x += 1
            pos += 1
        if cursor_col is not None and cursor_col == len(content) and x < x_offset + width:
            self.draw_segment(stdscr, y, x, " ", curses.A_REVERSE, cursor_col, base=cursor_col)
            x += 1
        return x

    def draw_segment(self, stdscr, y, x, text, attr, cursor_col=None, base=0):
        for i, ch in enumerate(text):
            if x + i >= stdscr.getmaxyx()[1] - 1:
                break
            ch_attr = attr
            if cursor_col is not None and base + i == cursor_col:
                ch_attr |= curses.A_REVERSE
            try:
                stdscr.addstr(y, x + i, ch, ch_attr)
            except curses.error:
                pass

    def _set_cursor_shape(self, beam=False):
        try:
            import sys
            sys.stdout.write("\033[6 q" if beam else "\033[2 q")
            sys.stdout.flush()
        except Exception:
            pass

    def register_key(self, mode, key, fn):
        self.bindings[(mode, key)] = fn

    def set_option(self, name, value):
        self.options[name] = value

    def on_start(self, fn):
        self.start_hooks.append(fn)

    def set_message(self, text):
        self.message = str(text)

    def run_python(self, source):
        old_msg = self.message
        try:
            exec(source, self.python_env)
            if self.message == old_msg:
                self.message = "Python executed"
        except Exception as exc:
            self.message = f"Python error: {exc}"

    # ── Plugin System ──────────────────────────────────────────────

    def emit(self, event, **kwargs):
        """Fire an event, calling all registered hooks. Returns list of results."""
        results = []
        for cb in self.event_hooks.get(event, []):
            try:
                r = cb(self, **kwargs)
                results.append(r)
            except Exception as exc:
                self.message = f"Event hook error ({event}): {exc}"
        # Autocommands: check pattern against filepath
        for pattern, cb in self.autocommands.get(event, []):
            try:
                fp = self.filepath or ""
                if pattern == "*" or (self.filepath and Path(fp).match(pattern)):
                    r = cb(self, **kwargs)
                    results.append(r)
            except Exception as exc:
                self.message = f"Autocmd error ({event}): {exc}"
        return results

    def on(self, event, callback):
        """Register a callback for an event. Returns callback for use as decorator."""
        self.event_hooks.setdefault(event, []).append(callback)
        return callback

    def off(self, event, callback=None):
        """Remove a callback (or all callbacks) for an event."""
        if callback is None:
            self.event_hooks.pop(event, None)
        elif event in self.event_hooks:
            self.event_hooks[event] = [cb for cb in self.event_hooks[event] if cb is not callback]

    def autocmd(self, event, pattern, callback):
        """Register an autocommand: callback fires when event matches glob pattern."""
        self.autocommands.setdefault(event, []).append((pattern, callback))

    def plugin_register(self, name, *, version="0.1", setup=None, description="", **extra):
        """Register a plugin. setup(editor) is called to initialize."""
        info = {"name": name, "version": version, "description": description,
                "enabled": True, "setup": setup, **extra}
        self.plugins[name] = info
        if setup:
            try:
                setup(self)
            except Exception as exc:
                info["enabled"] = False
                self.message = f"Plugin '{name}' setup error: {exc}"
                return False
        self.emit("plugin_loaded", plugin=name)
        return True

    def plugin_load_file(self, path):
        """Load a plugin from a Python file. The file should call editor.plugin_register(...)."""
        path = Path(path)
        if not path.exists():
            self.message = f"Plugin not found: {path}"
            return False
        try:
            code = path.read_text(encoding="utf-8")
            exec(compile(code, str(path), "exec"),
                 {"editor": self, "__builtins__": __builtins__})
            return True
        except Exception as exc:
            self.message = f"Plugin load error ({path.name}): {exc}"
            return False

    def plugin_load_dir(self, directory):
        """Load all *.py plugins from a directory."""
        d = Path(directory)
        if not d.is_dir():
            return 0
        count = 0
        for f in sorted(d.glob("*.py")):
            if f.name.startswith("_"):
                continue
            if self.plugin_load_file(f):
                count += 1
        return count

    def plugin_load_all(self):
        """Load plugins from all configured plugin directories."""
        total = 0
        loaded_names = set()  # Track filenames to avoid loading duplicates
        for d in self.plugin_dirs:
            dp = Path(d)
            if not dp.is_dir():
                continue
            for f in sorted(dp.glob("*.py")):
                if f.name.startswith("_"):
                    continue
                if f.name in loaded_names:
                    continue  # Skip duplicate plugin files across directories
                loaded_names.add(f.name)
                if self.plugin_load_file(f):
                    total += 1
        if total:
            self.message = f"Loaded {total} plugin(s)"
        return total

    def plugin_disable(self, name):
        """Disable a plugin by name."""
        if name in self.plugins:
            self.plugins[name]["enabled"] = False
            teardown = self.plugins[name].get("teardown")
            if teardown:
                try:
                    teardown(self)
                except Exception:
                    pass
            self.message = f"Plugin '{name}' disabled"
        else:
            self.message = f"Plugin '{name}' not found"

    def plugin_enable(self, name):
        """Re-enable a disabled plugin."""
        if name in self.plugins:
            info = self.plugins[name]
            info["enabled"] = True
            setup = info.get("setup")
            if setup:
                try:
                    setup(self)
                except Exception as exc:
                    info["enabled"] = False
                    self.message = f"Plugin '{name}' enable error: {exc}"
                    return
            self.message = f"Plugin '{name}' enabled"
        else:
            self.message = f"Plugin '{name}' not found"

    def plugin_list(self):
        """Return a list of (name, version, enabled, description) tuples."""
        return [(p["name"], p["version"], p["enabled"], p.get("description", ""))
                for p in self.plugins.values()]

    # ── Jump List ──────────────────────────────────────────────────

    def jumplist_push(self):
        """Record current position in the jump list."""
        pos = (self.cy, self.cx)
        if self.jumplist and self.jumplist[-1] == pos:
            return
        # Truncate forward history if we moved
        if self.jumplist_pos >= 0 and self.jumplist_pos < len(self.jumplist) - 1:
            self.jumplist = self.jumplist[:self.jumplist_pos + 1]
        self.jumplist.append(pos)
        if len(self.jumplist) > 100:
            self.jumplist = self.jumplist[-100:]
        self.jumplist_pos = len(self.jumplist) - 1

    def jumplist_back(self):
        """Go to previous position in jump list (Ctrl+o)."""
        if not self.jumplist:
            self.message = "Jump list empty"
            return
        if self.jumplist_pos < 0:
            self.jumplist_pos = len(self.jumplist) - 1
        # Save current position if at end
        if self.jumplist_pos == len(self.jumplist) - 1:
            cur = (self.cy, self.cx)
            if not self.jumplist or self.jumplist[-1] != cur:
                self.jumplist.append(cur)
                self.jumplist_pos = len(self.jumplist) - 1
        if self.jumplist_pos > 0:
            self.jumplist_pos -= 1
            y, x = self.jumplist[self.jumplist_pos]
            if y < len(self.lines):
                self.cy = y
                self.cx = min(x, len(self.lines[y]))

    def jumplist_forward(self):
        """Go to next position in jump list (Ctrl+i / Tab in normal)."""
        if not self.jumplist:
            self.message = "Jump list empty"
            return
        if self.jumplist_pos < len(self.jumplist) - 1:
            self.jumplist_pos += 1
            y, x = self.jumplist[self.jumplist_pos]
            if y < len(self.lines):
                self.cy = y
                self.cx = min(x, len(self.lines[y]))

    # ── QoL: Join Lines ────────────────────────────────────────────

    def join_lines(self):
        """Join current line with next line (J key)."""
        if self.cy >= len(self.lines) - 1:
            return
        current = self.lines[self.cy].rstrip()
        next_line = self.lines[self.cy + 1].lstrip()
        sep = " " if current and next_line else ""
        self.cx = len(current)
        self.lines[self.cy] = current + sep + next_line
        del self.lines[self.cy + 1]
        self.dirty = True

    # ── QoL: Toggle Case ──────────────────────────────────────────

    def toggle_case(self):
        """Toggle case of character under cursor (~ key)."""
        line = self.current_line()
        if self.cx < len(line):
            ch = line[self.cx]
            toggled = ch.lower() if ch.isupper() else ch.upper()
            self.lines[self.cy] = line[:self.cx] + toggled + line[self.cx + 1:]
            self.cx = min(self.cx + 1, len(self.lines[self.cy]))
            self.dirty = True

    # ── QoL: Ctrl+s Save ──────────────────────────────────────────

    def quick_save(self):
        """Quick save (Ctrl+s)."""
        self.emit("before_save", filepath=self.filepath)
        self.write_file()
        self.emit("after_save", filepath=self.filepath)

    def run_file(self):
        """Run the current file using language-appropriate command."""
        if not self.filepath:
            self.message = "No file to run"
            return
        if self.dirty:
            self.write_file()
        fp = self.filepath
        lang = self.syntax_language
        run_commands = {
            "python": f"python3 {fp}",
            "javascript": f"node {fp}",
            "typescript": f"npx ts-node {fp}",
            "lua": f"lua {fp}",
            "ruby": f"ruby {fp}",
            "perl": f"perl {fp}",
            "php": f"php {fp}",
            "shell": f"bash {fp}",
            "go": f"go run {fp}",
            "rust": f"cargo run",
            "c": f"gcc -o /tmp/evim_run {fp} && /tmp/evim_run",
            "cpp": f"g++ -o /tmp/evim_run {fp} && /tmp/evim_run",
            "java": f"javac {fp} && java {os.path.splitext(os.path.basename(fp))[0]}",
            "kotlin": f"kotlinc {fp} -include-runtime -d /tmp/evim_run.jar && java -jar /tmp/evim_run.jar",
            "swift": f"swift {fp}",
            "scala": f"scala {fp}",
            "pascal": f"fpc {fp} -o/tmp/evim_run && /tmp/evim_run",
            "fortran": f"gfortran -o /tmp/evim_run {fp} && /tmp/evim_run",
            "csharp": f"dotnet-script {fp}",
            "assembly": f"nasm -f elf64 {fp} -o /tmp/evim_run.o && ld /tmp/evim_run.o -o /tmp/evim_run && /tmp/evim_run",
            "r": f"Rscript {fp}",
            "zig": f"zig run {fp}",
            "nim": f"nim r {fp}",
            "dart": f"dart run {fp}",
            "elixir": f"elixir {fp}",
            "erlang": f"escript {fp}",
            "haskell": f"runghc {fp}",
            "ocaml": f"ocaml {fp}",
            "clojure": f"clojure {fp}",
            "lisp": f"sbcl --script {fp}",
            "julia": f"julia {fp}",
            "dlang": f"dmd -run {fp}",
            "v": f"v run {fp}",
            "groovy": f"groovy {fp}",
            "powershell": f"pwsh {fp}",
            "sql": f"sqlite3 < {fp}",
            "html": f"xdg-open {fp}",
        }
        cmd = run_commands.get(lang)
        if not cmd:
            self.message = f"No run command for {lang or 'unknown'} files"
            return
        self.message = f"Running: {cmd}"
        if not self.term_visible:
            self.term_toggle()
        self.term_write(cmd + "\n")

    def start(self, stdscr):
        curses.curs_set(1)
        self._set_cursor_shape(beam=False)
        self._inject_key = None
        stdscr.keypad(True)
        curses.raw()
        stdscr.timeout(100)
        self.init_colors()
        self.load_undo_history()
        self.update_git_gutter()
        self._last_click_time = 0
        self._last_click_pos = (-1, -1)
        self._mouse_dragging = False
        if self.options.get("mouse"):
            curses.mousemask(curses.ALL_MOUSE_EVENTS | curses.REPORT_MOUSE_POSITION)
        # Load plugins from plugin directories
        self.plugin_load_all()
        for fn in self.start_hooks:
            try:
                fn(self)
            except Exception as exc:
                self.message = f"Start hook error: {exc}"
        self.emit("startup")
        while not self.should_exit:
            if self.mode == "overlay":
                self.draw_overlay(stdscr)
            elif self._palette_visible:
                self.redraw(stdscr)
                self.draw_palette(stdscr, *stdscr.getmaxyx())
                curses.doupdate()
                self.handle_palette_key(stdscr)
                continue
            elif self._grep_visible:
                self.redraw(stdscr)
                self.draw_grep_results(stdscr, *stdscr.getmaxyx())
                curses.doupdate()
                self.handle_grep_key(stdscr)
                continue
            elif self._outline_visible:
                self.redraw(stdscr)
                self.draw_outline(stdscr, *stdscr.getmaxyx())
                curses.doupdate()
                self.handle_outline_key(stdscr)
                continue
            elif self.menu_visible:
                self.redraw(stdscr)
                self.handle_menu_key(stdscr)
                continue
            elif self._ctx_menu_visible:
                self.redraw(stdscr)
                self._draw_context_menu(stdscr, *stdscr.getmaxyx())
                curses.doupdate()
                ch = stdscr.getch()
                if ch >= 0:
                    self._handle_context_menu_key(ch)
                continue
            else:
                self.redraw(stdscr)
            self.handle_key(stdscr)
        self.lsp_stop()
        self.save_undo_history()
        self._set_cursor_shape(beam=False)

    def redraw(self, stdscr):
        height, width = stdscr.getmaxyx()
        bg = getattr(self, 'color_bg', curses.A_NORMAL)
        stdscr.bkgd(' ', bg)
        stdscr.erase()

        # ── Menu overlay ──
        if self.menu_visible:
            self.draw_menu(stdscr, height, width)
            curses.doupdate()
            return

        # ── Auto-save tick ──
        if self.options.get("autosave") and self.dirty and self.filepath:
            self._autosave_counter += 1
            delay = self.options.get("autosave_delay", 5) * 10  # ~100ms per tick
            if self._autosave_counter >= delay:
                self._autosave_counter = 0
                self.write_file()

        # ── Draw side panels and compute editor area ──
        editor_left = 0
        editor_right = width
        if self.explorer_visible:
            ew = self.draw_file_explorer(stdscr, height, width)
            editor_left = ew
        if self.minimap_visible and width - editor_left > 40:
            top_for_minimap = max(0, self.cy - height + 4)
            mw = self.draw_minimap(stdscr, height, width, top_for_minimap)
            editor_right = width - mw
        editor_w = editor_right - editor_left
        if editor_w < 10:
            editor_w = width
            editor_left = 0
            editor_right = width

        # ── Tab/buffer bar ──
        tab_h = 0
        if self.options.get("tabline") and len(self.buffer_order) > 0:
            tab_h = 1
            self._draw_tabline(stdscr, editor_left, editor_w, width)

        # ── Bracket match finding ──
        self._bracket_match_pos = None
        if self.options.get("bracket_highlight"):
            self._find_bracket_match()

        # ── Word under cursor positions ──
        self._word_hl_positions = []
        if self.options.get("word_highlight"):
            self._find_word_highlights()

        top = max(0, self.cy - height + 4 + tab_h)
        content_rows = height - 2 - tab_h

        # ── Build visible line list (accounting for folds) ──
        visible_lines = []  # [(actual_lineno, line_text), ...]
        i = 0
        while i < len(self.lines):
            visible_lines.append((i, self.lines[i]))
            if i in self.folds:
                i = self.folds[i] + 1
            else:
                i += 1
        # Find top in visible lines
        vis_top = 0
        for vi, (lineno, _) in enumerate(visible_lines):
            if lineno >= self.cy:
                vis_top = max(0, vi - height + 4 + tab_h)
                break
        display_lines = visible_lines[vis_top:vis_top + content_rows]
        num_file_lines = len(display_lines)
        has_gutter = bool(self.git_diff_lines) or (self.lsp_enabled and self.lsp_diagnostics)
        gutter_w = 2 if has_gutter else 0

        # ── Build diagnostic lookup for error lens ──
        diag_by_line = {}
        if self.lsp_enabled and self.lsp_diagnostics:
            for dline, dcol, sev, dmsg in self.lsp_diagnostics:
                if dline not in diag_by_line or sev < diag_by_line[dline][0]:
                    diag_by_line[dline] = (sev, dmsg)

        for idx, (lineno, line) in enumerate(display_lines):
            row = idx + tab_h
            x_off = editor_left
            # Git gutter + LSP diagnostic gutter
            if has_gutter:
                diff_type = self.git_diff_lines.get(lineno)
                diag_info = diag_by_line.get(lineno)
                gutter_ch = " "
                gutter_attr = bg
                if diag_info:
                    sev = diag_info[0]
                    gutter_ch = "●"
                    if sev == 1:
                        gutter_attr = getattr(self, 'color_error_lens', curses.color_pair(2) | curses.A_BOLD)
                    elif sev == 2:
                        gutter_attr = getattr(self, 'color_warn_lens', curses.color_pair(8) | curses.A_BOLD)
                    else:
                        gutter_attr = getattr(self, 'color_info_lens', curses.color_pair(5) | curses.A_BOLD)
                elif diff_type == 'added':
                    gutter_ch = "+"
                    gutter_attr = self.color_keyword
                elif diff_type == 'modified':
                    gutter_ch = "~"
                    gutter_attr = self.color_string
                elif diff_type == 'deleted':
                    gutter_ch = "-"
                    gutter_attr = self.color_preprocessor
                try:
                    stdscr.addstr(row, x_off, gutter_ch + " ", gutter_attr)
                except curses.error:
                    pass
            prefix = ""
            if self.options.get("number") or self.options.get("relativenumber"):
                if self.options.get("relativenumber"):
                    if lineno == self.cy:
                        num = lineno + 1
                    else:
                        num = abs(lineno - self.cy)
                else:
                    num = lineno + 1
                prefix = f"{num:4} "
            display_line = line.replace("\t", " " * self.options["tabsize"])
            # Horizontal scroll
            scroll_left = self.scroll_left if not self.options.get("wrap") else 0
            if scroll_left > 0 and scroll_left < len(display_line):
                display_line = display_line[scroll_left:]
            elif scroll_left >= len(display_line):
                display_line = ""
            cursor_col = None
            if lineno == self.cy:
                display_cx = 0
                for i in range(min(self.cx, len(line))):
                    if line[i] == '\t':
                        display_cx += self.options["tabsize"]
                    else:
                        display_cx += 1
                cursor_col = display_cx - scroll_left
            # Offset x by gutter width
            full_prefix = " " * gutter_w + prefix if gutter_w else prefix
            # Truncate line to editor area width
            avail_w = editor_w
            drawn = self.highlight_line(stdscr, row, display_line, full_prefix, avail_w, cursor_col, x_off)

            # ── Error Lens: inline diagnostic message ──
            if self.options.get("error_lens") and lineno in diag_by_line:
                sev, dmsg = diag_by_line[lineno]
                lens_attr = getattr(self, 'color_error_lens', curses.A_BOLD)
                if sev == 2:
                    lens_attr = getattr(self, 'color_warn_lens', curses.A_NORMAL)
                elif sev >= 3:
                    lens_attr = getattr(self, 'color_info_lens', curses.A_NORMAL)
                # Draw inline after the line content
                gap = 2
                avail = x_off + editor_w - 1 - drawn - gap
                if avail > 8:
                    severity_label = {1: "ERR", 2: "WARN", 3: "INFO", 4: "HINT"}.get(sev, "?")
                    lens_text = f"  {severity_label}: {dmsg}"
                    lens_text = lens_text[:avail]
                    try:
                        stdscr.addstr(row, drawn + gap, lens_text, lens_attr | curses.A_DIM)
                    except curses.error:
                        pass

            # Cursorline highlight
            if self.options.get("cursorline") and lineno == self.cy:
                if drawn < x_off + editor_w - 1:
                    try:
                        stdscr.addstr(row, drawn, " " * (x_off + editor_w - 1 - drawn), curses.A_UNDERLINE | bg)
                    except curses.error:
                        pass
                try:
                    stdscr.chgat(row, x_off + gutter_w, editor_w - 1 - gutter_w, curses.A_UNDERLINE | bg)
                except curses.error:
                    pass
            elif drawn < x_off + editor_w - 1:
                try:
                    stdscr.addstr(row, drawn, " " * (x_off + editor_w - 1 - drawn), bg)
                except curses.error:
                    pass
            # Draw indent guides at each tab stop within the leading whitespace
            if self.options.get("indent_guides", False):
                prefix_len = len(full_prefix)
                indent = len(display_line) - len(display_line.lstrip())
                tab = self.options.get("tabsize", 4)
                if indent > 0 and tab > 0:
                    for col in range(0, indent, tab):
                        gx = x_off + prefix_len + col
                        if x_off <= gx < x_off + editor_w - 1:
                            try:
                                stdscr.addstr(row, gx, "│", curses.A_DIM | bg)
                            except curses.error:
                                pass

            # ── Bracket match highlight ──
            if self._bracket_match_pos and self._bracket_match_pos[0] == lineno:
                bm_col = self._bracket_match_pos[1]
                prefix_len = len(full_prefix)
                bm_display_col = bm_col - scroll_left
                if bm_display_col >= 0:
                    bm_x = x_off + prefix_len + bm_display_col
                    if x_off <= bm_x < x_off + editor_w - 1:
                        bracket_attr = getattr(self, 'color_bracket_match', curses.A_BOLD | curses.A_UNDERLINE)
                        try:
                            stdscr.chgat(row, bm_x, 1, bracket_attr)
                        except curses.error:
                            pass

            # ── Word highlight ──
            if self._word_hl_positions:
                prefix_len = len(full_prefix)
                for wy, wx_start, wx_end in self._word_hl_positions:
                    if wy == lineno and (wy != self.cy or wx_start != self.cx):
                        whl_start = wx_start - scroll_left + prefix_len + x_off
                        whl_len = wx_end - wx_start
                        if whl_start >= x_off and whl_start + whl_len < x_off + editor_w:
                            word_attr = getattr(self, 'color_word_hl', curses.A_UNDERLINE)
                            try:
                                stdscr.chgat(row, whl_start, whl_len, word_attr)
                            except curses.error:
                                pass

            # ── Incremental search match highlights ──
            if self._isearch_active and self._isearch_matches:
                prefix_len = len(full_prefix)
                for mline, mcol, mlen in self._isearch_matches:
                    if mline == lineno:
                        hl_start = mcol - scroll_left + prefix_len + x_off
                        if hl_start >= x_off and hl_start + mlen < x_off + editor_w:
                            is_current = (self._isearch_idx < len(self._isearch_matches) and
                                          self._isearch_matches[self._isearch_idx] == (mline, mcol, mlen))
                            if is_current:
                                search_attr = curses.A_REVERSE | curses.A_BOLD
                            else:
                                search_attr = curses.A_REVERSE
                            try:
                                stdscr.chgat(row, hl_start, mlen, search_attr)
                            except curses.error:
                                pass

            # ── Fold indicator ──
            if lineno in self.folds:
                fold_end = self.folds[lineno]
                fold_text = f" ··· {fold_end - lineno} lines folded ···"
                fold_col = len(full_prefix) + len(display_line) + x_off
                if fold_col < x_off + editor_w - len(fold_text):
                    try:
                        stdscr.addstr(row, fold_col, fold_text[:editor_w], curses.A_DIM | curses.A_ITALIC)
                    except curses.error:
                        pass

            # ── Visual block selection highlight ──
            if self.mode == "visual" and self.selection_type == "block" and self.selection is not None:
                rect = self._block_selection_rect()
                if rect:
                    top_b, bot_b, left_b, right_b = rect
                    if top_b <= lineno <= bot_b:
                        prefix_len = len(full_prefix)
                        hl_start = x_off + prefix_len + left_b - scroll_left
                        hl_len = right_b - left_b + 1
                        if hl_start < x_off + editor_w and hl_start + hl_len > x_off:
                            hl_start = max(hl_start, x_off + prefix_len)
                            hl_len = min(hl_len, x_off + editor_w - hl_start - 1)
                            if hl_len > 0:
                                try:
                                    stdscr.chgat(row, hl_start, hl_len, curses.A_REVERSE)
                                except curses.error:
                                    pass

            # ── Multi-cursor secondary cursor markers ──
            if self.cursors:
                prefix_len = len(full_prefix)
                for (mcy, mcx) in self.cursors:
                    if mcy == lineno:
                        mc_x = x_off + prefix_len + mcx - scroll_left
                        if x_off + prefix_len <= mc_x < x_off + editor_w - 1:
                            try:
                                stdscr.chgat(row, mc_x, 1, curses.A_REVERSE | curses.A_BOLD)
                            except curses.error:
                                pass

            # ── LSP inlay hints ──
            if self.options.get("inlay_hints", True):
                self.draw_inlay_hints(stdscr, row, lineno, len(full_prefix), x_off, editor_w)

        # Fill empty rows below file content with tilde markers
        ln_attr = getattr(self, 'color_lineno', bg)
        for idx in range(num_file_lines + tab_h, height - 2):
            try:
                stdscr.addstr(idx, editor_left, "~".ljust(editor_w - 1), ln_attr)
            except curses.error:
                pass
        # Enhanced status bar
        dirty_marker = "[+]" if self.dirty else ""
        ft = self.syntax_language or "plain"
        linecol = f"Ln {self.cy + 1}/{len(self.lines)}, Col {self.cx + 1}"
        color_info = f"{self._color_depth}c" if self._color_depth != 8 else ""
        # Update breadcrumb from outline
        self.update_breadcrumb()
        crumb = f"  {self._breadcrumb}" if self._breadcrumb else ""
        # Multi-cursor indicator
        mc_ind = f" +{len(self.cursors)}cur" if self.cursors else ""
        left_status = f" {self.mode.upper()} | {self.filepath or '[no file]'} {dirty_marker}{mc_ind}"
        run_btn = " \u25b6 Run " if self.filepath else ""
        right_status = f"{ft} {color_info}| {linecol}{crumb} "
        mid = self.message
        gap = width - 1 - len(left_status) - len(run_btn) - len(right_status)
        if gap > len(mid) + 2:
            center = f" {mid} "
            pad = gap - len(center)
            status = left_status + run_btn + " " * (pad // 2) + center + " " * (pad - pad // 2) + right_status
        else:
            status = (left_status + run_btn + " " + mid)[:width - 1 - len(right_status)] + right_status
        status_attr = getattr(self, 'color_status', curses.A_REVERSE)
        status_padded = status[:width - 1].ljust(width - 1)
        try:
            stdscr.addstr(height - 2, 0, status_padded, status_attr)
        except curses.error:
            pass
        # Highlight the Run button in green
        if run_btn and self.filepath:
            run_col = len(left_status)
            if run_col + len(run_btn) < width - 1:
                run_attr = curses.A_BOLD | curses.color_pair(4)
                try:
                    stdscr.addstr(height - 2, run_col, run_btn, run_attr)
                except curses.error:
                    pass
        cmd_attr = getattr(self, 'color_cmdline', curses.A_NORMAL)
        if self.mode == "command" and self.options.get("show_command"):
            command_line = ":" + self.command
            cmdline_padded = command_line[:width - 1].ljust(width - 1)
            try:
                stdscr.addstr(height - 1, 0, cmdline_padded, cmd_attr)
            except curses.error:
                pass
        elif self.macro_recording:
            rec = f"recording @{self.macro_recording}"
            try:
                stdscr.addstr(height - 1, 0, rec[:width - 1].ljust(width - 1), cmd_attr)
            except curses.error:
                pass
        else:
            hint = "Press : for commands, i for insert, ESC to return."
            try:
                stdscr.addstr(height - 1, 0, hint[:width - 1].ljust(width - 1), cmd_attr)
            except curses.error:
                pass
        line = self.lines[self.cy] if self.cy < len(self.lines) else ""
        display_cx = 0
        for i in range(min(self.cx, len(line))):
            if line[i] == '\t':
                display_cx += self.options["tabsize"]
            else:
                display_cx += 1
        prefix_w = gutter_w + (5 if self.options.get("number") or self.options.get("relativenumber") else 0)
        scroll_left = self.scroll_left if not self.options.get("wrap") else 0
        # Draw terminal panel if visible
        if self.term_visible:
            self.draw_terminal_panel(stdscr)
        # Draw diagnostics panel if visible
        if self._diag_panel_visible:
            self.draw_diagnostics_panel(stdscr, height, width)
        # Draw git output panel if visible
        if self._git_status_visible:
            self.draw_git_panel(stdscr, height, width)
        # Draw split pane indicator
        if self.splits:
            self.draw_split_indicators(stdscr, height, width)
        # Draw LSP completion popup
        if self.lsp_completion_active:
            self.draw_lsp_completion_popup(stdscr, height, width)
        # Draw LSP status indicator
        if self.lsp_enabled:
            lsp_ind = " LSP"
            lsp_col = width - len(lsp_ind) - 1
            if lsp_col > 0:
                lsp_attr = curses.color_pair(4) | curses.A_BOLD
                try:
                    stdscr.addstr(height - 2, lsp_col, lsp_ind, lsp_attr)
                except curses.error:
                    pass
        # Color depth indicator
        if self._color_depth > 8:
            depth_ind = f" {self._color_depth}c"
            depth_col = width - len(depth_ind) - (5 if self.lsp_enabled else 1)
            if depth_col > 0:
                try:
                    stdscr.addstr(height - 2, depth_col, depth_ind, curses.A_DIM | getattr(self, 'color_status', curses.A_REVERSE))
                except curses.error:
                    pass
        # F10 hint
        f10_hint = " F10:Menu"
        f10_col = len(left_status) + len(run_btn)
        if f10_col + len(f10_hint) < width // 2:
            try:
                stdscr.addstr(height - 2, f10_col, f10_hint, curses.A_DIM | getattr(self, 'color_status', curses.A_REVERSE))
            except curses.error:
                pass
        if self.mode != "terminal" and self.mode != "explorer":
            # Find cursor row in visible display
            cursor_display_row = 0
            for di, (ln, _) in enumerate(display_lines):
                if ln == self.cy:
                    cursor_display_row = di
                    break
            curses.setsyx(cursor_display_row + tab_h, display_cx - scroll_left + prefix_w + editor_left)
        curses.doupdate()

    def draw_overlay(self, stdscr):
        stdscr.erase()
        height, width = stdscr.getmaxyx()
        if self.show_welcome:
            lines = [
                "Welcome to EVim",
                "1.0.0",
                "",
                "Normal mode commands:",
                "  h/j/k/l  - move",
                "  i        - insert mode",
                "  dd       - delete line",
                "  dw       - delete word",
                "  yy       - yank line",
                "  p        - paste",
                "  u        - undo",
                "  /pattern - search forward",
                "  n/N      - next/previous search",
                "  :w, :q, :wq, :source, :help",
                "",
                "Press any key to continue...",
            ]
        else:
            lines = [
                "EVim Help",
                "",
                "── Movement ──",
                "  h/j/k/l     move left/down/up/right",
                "  w/b/e       word forward/backward/end",
                "  0 / $       line start / line end",
                "  gg / G      file start / file end",
                "  %           match bracket",
                "  Ctrl+d/u    scroll half page down/up",
                "  Ctrl+f/b    scroll full page down/up",
                "",
                "── Editing ──",
                "  i / I       insert / insert at start",
                "  a / A       (append) / append at end",
                "  o / O       open line below / above",
                "  x           delete char",
                "  dd / dw     delete line / word",
                "  cw          change word",
                "  yy          yank line",
                "  p           paste",
                "  J           join lines",
                "  ~           toggle case",
                "  u / Ctrl+r  undo / redo",
                "  .           repeat last edit",
                "  Ctrl+/      toggle comment",
                "  Ctrl+s      quick save",
                "",
                "── Search & Selection ──",
                "  /pattern    search forward",
                "  ?pattern    search backward",
                "  n / N       next / prev match",
                "  v           toggle visual selection",
                "  d / y       delete / yank selection",
                "",
                "── Navigation ──",
                "  Ctrl+o      jump back",
                "  Ctrl+i      jump forward",
                "  Ctrl+p      fuzzy file finder",
                "  Ctrl+n      toggle terminal",
                "  Ctrl+e      toggle file explorer",
                "  Ctrl+m      toggle minimap",
                "  Ctrl+Up/Dn  fast scroll (5 lines)",
                "  Ctrl+g      file info",
                "",
                "── Macros / Marks / Registers ──",
                "  q{a-z}      record macro",
                "  @{a-z}      play macro",
                "  m{a-z}      set mark",
                "  '{a-z}      goto mark",
                "  \"{a-z}      select register",
                "",
                "── Commands ──",
                "  :w :q :wq :q!   save/quit",
                "  :e <file>       open buffer",
                "  :bn :bp :ls     buffer navigation",
                "  :cd :pwd :!cmd  directory/shell",
                "  :sort :noh      sort lines / clear search",
                "  :reg :marks     show registers/marks",
                "  :explorer       toggle file explorer",
                "  :minimap        toggle minimap",
                "  :theme <name>   change theme",
                "  :source <file>  source a script",
                "  :help           this help",
                "",
                "── Plugins ──",
                "  :PluginLoad     load all plugins",
                "  :PluginList     list loaded plugins",
                "  :PluginDisable  disable a plugin",
                "  :PluginEnable   enable a plugin",
                "  Dirs: ~/.config/evim/plugins/",
                "        .evim/plugins/",
                "",
                "── LSP ──",
                "  :lsp            start language server",
                "  :lsp stop       stop language server",
                "  :lsp restart    restart server",
                "  :lsp status     show server info",
                "  gd              go to definition",
                "  gr              find references",
                "  K               hover info",
                "  Tab (insert)    LSP completion",
                "",
                "── IDE Features ──",
                "  F10 / Alt+x     settings menu",
                "  F2              save config to evimrc.py",
                "  Alt+Up / Alt+k  move line up",
                "  Alt+Dn / Alt+j  move line down",
                "  Alt+d           duplicate line",
                "  Ctrl+x          command palette (M-x)",
                "  Ctrl+y          kill ring paste",
                "  Right-click     context menu",
                "",
                "── Folding ──",
                "  za              toggle fold at cursor",
                "  zo / zc         open / close fold",
                "  zM / zR         fold all / unfold all",
                "",
                "── Surround ──",
                "  cs<old><new>    change surround pair",
                "  ds<char>        delete surround pair",
                "  S<char>         surround selection (visual)",
                "",
                "── Mouse ──",
                "  Click           position cursor",
                "  Double-click    select word",
                "  Triple-click    select line",
                "  Drag            visual selection",
                "  Right-click     context menu",
                "  Scroll wheel    scroll up/down",
                "  Click tab bar   switch buffer",
                "  Click minimap   jump to position",
                "  Click mode      toggle insert/normal",
                "",
                "── IDE Commands ──",
                "  :menu           open settings menu",
                "  :palette        command palette",
                "  :grep <pat>     project-wide search",
                "  :outline        symbol outline",
                "  :recent         recent files",
                "  :killring       show kill ring",
                "  :fold / :za     toggle fold",
                "  :foldall / :zM  fold all",
                "  :unfoldall      unfold all",
                "  :savecfg        save config to evimrc.py",
                "  :errorlens      toggle error lens",
                "  :tabline        toggle tab bar",
                "  :autosave       toggle auto save",
                "",
                "Press any key to return...",
            ]
        box_top = max(0, (height - len(lines)) // 2 - 1)
        box_left = max(0, (width - 60) // 2)
        for idx, text in enumerate(lines):
            if box_top + idx >= height - 1:
                break
            if box_left >= width:
                continue
            text_width = max(0, width - box_left - 1)
            if text_width == 0:
                continue
            try:
                stdscr.addstr(box_top + idx, box_left, text[:text_width])
            except curses.error:
                pass
        curses.setsyx(0, 0)
        curses.doupdate()

    def handle_key(self, stdscr):
        if hasattr(self, '_inject_key') and self._inject_key is not None:
            ch = self._inject_key
            self._inject_key = None
        else:
            ch = stdscr.getch()
        if ch < 0:
            return
        # Record macro keys (but not the q that stops recording)
        if self.macro_recording and not self.macro_playing:
            if ch != ord('q') or self.mode != "normal":
                self.macro_keys.append(ch)
        if self.mode == "overlay":
            self.mode = "normal"
            self.show_welcome = False
            self.message = "EVim - normal mode"
            return
        # Mouse handling
        if ch == curses.KEY_MOUSE and self.options.get("mouse"):
            try:
                _, mx, my, _, bstate = curses.getmouse()
                height, width = stdscr.getmaxyx()
                tab_h = 1 if self.options.get("tabline") else 0
                top = max(0, self.cy - height + 4 + tab_h)
                has_nums = self.options.get("number") or self.options.get("relativenumber")
                prefix_w = (2 if self.git_diff_lines else 0) + (5 if has_nums else 0)
                scroll_left = self.scroll_left if not self.options.get("wrap") else 0
                now = time.time()
                # ── Right-click context menu ──
                if bstate & (curses.BUTTON3_PRESSED | curses.BUTTON3_CLICKED):
                    self._show_context_menu(stdscr, mx, my)
                    return
                # ── Click on tab bar ──
                if tab_h and my == 0 and (bstate & (curses.BUTTON1_PRESSED | curses.BUTTON1_CLICKED)):
                    editor_left = min(self.explorer_width, width // 3) if self.explorer_visible else 0
                    x = editor_left
                    for i, buf_path in enumerate(self.buffer_order):
                        name = os.path.basename(buf_path) if buf_path != "[No Name]" else "[No Name]"
                        if buf_path == self.filepath and self.dirty:
                            name += "●"
                        tab_len = len(f" {name} ") + 1  # +1 for separator
                        if x <= mx < x + tab_len:
                            # Switch to this buffer
                            if i != self.current_buffer_idx:
                                if self.filepath and self.filepath in self.buffers:
                                    self.buffers[self.filepath] = self.lines[:]
                                self.current_buffer_idx = i
                                self.filepath = self.buffer_order[i]
                                self.lines = self.buffers[self.filepath][:]
                                self.cy = min(self.cy, max(0, len(self.lines) - 1))
                                self.cx = 0
                                self.detect_syntax()
                                self.message = f"Buffer: {os.path.basename(self.filepath)}"
                            return
                        x += tab_len
                    return
                # ── Click on minimap ──
                if self.minimap_visible:
                    mm_x = width - self.minimap_width
                    if mx >= mm_x and (bstate & (curses.BUTTON1_PRESSED | curses.BUTTON1_CLICKED)):
                        # Jump to approximate position
                        ratio = my / max(1, height - 3)
                        target = int(ratio * len(self.lines))
                        self.cy = max(0, min(target, len(self.lines) - 1))
                        self.cx = 0
                        self.message = f"Jumped to line {self.cy + 1}"
                        return
                # Check if click is inside the file explorer
                if self.explorer_visible:
                    ew = min(self.explorer_width, width // 3)
                    if mx < ew:
                        if bstate & (curses.BUTTON1_PRESSED | curses.BUTTON1_CLICKED):
                            if self.mode != "explorer":
                                self.mode = "explorer"
                                self.message = "EXPLORER (Ctrl+e to close)"
                            # Click on entry
                            if my >= 1 and my < height - 2:
                                clicked_idx = self.explorer_scroll + (my - 1)
                                if 0 <= clicked_idx < len(self.explorer_entries):
                                    self.explorer_cursor = clicked_idx
                                    # Double-click opens
                                    if hasattr(self, '_explorer_last_click') and self._explorer_last_click == clicked_idx and (now - self._explorer_click_time) < 0.4:
                                        self.explorer_handle_key(10)  # simulate Enter
                                        self._explorer_last_click = -1
                                    else:
                                        self._explorer_last_click = clicked_idx
                                        self._explorer_click_time = now
                        # Scroll wheel in explorer
                        if bstate & (curses.BUTTON4_PRESSED if hasattr(curses, 'BUTTON4_PRESSED') else 0):
                            self.explorer_scroll = max(0, self.explorer_scroll - 3)
                            return
                        if bstate & (curses.BUTTON5_PRESSED if hasattr(curses, 'BUTTON5_PRESSED') else 0):
                            self.explorer_scroll += 3
                            return
                        return
                # Check if click is inside the terminal panel
                if self.term_visible:
                    panel_h = max(5, height // 2)
                    panel_w = max(20, width // 2)
                    panel_y = height - panel_h - 2
                    panel_x = width - panel_w
                    if panel_y <= my < panel_y + panel_h and panel_x <= mx < panel_x + panel_w:
                        if bstate & (curses.BUTTON1_PRESSED | curses.BUTTON1_CLICKED | curses.BUTTON1_RELEASED):
                            if self.mode != "terminal":
                                self.mode = "terminal"
                                self.message = "TERMINAL (Ctrl+n to return)"
                            return
                        # Scroll wheel inside terminal panel
                        if bstate & (curses.BUTTON4_PRESSED if hasattr(curses, 'BUTTON4_PRESSED') else 0):
                            self.term_scroll = min(self.term_scroll + 3, max(0, len(self.term_lines) - 3))
                            return
                        if bstate & (curses.BUTTON5_PRESSED if hasattr(curses, 'BUTTON5_PRESSED') else 0):
                            self.term_scroll = max(0, self.term_scroll - 3)
                            return
                        return
                # Click on Run button / status bar buttons
                if my == height - 2 and self.filepath:
                    if bstate & (curses.BUTTON1_PRESSED | curses.BUTTON1_CLICKED):
                        run_label = " ▶ Run "
                        run_col = len(f" {self.mode.upper()} | {self.filepath or '[no file]'} {'[+]' if self.dirty else ''}")
                        f10_col = run_col + len(run_label)
                        if run_col <= mx < run_col + len(run_label):
                            self.run_file()
                            return
                        # Click on F10:Menu hint
                        f10_hint = " F10:Menu"
                        if f10_col <= mx < f10_col + len(f10_hint):
                            self.menu_visible = True
                            self.menu_cursor = 0
                            return
                        # Click on mode indicator to toggle insert/normal
                        mode_len = len(f" {self.mode.upper()} ")
                        if mx < mode_len:
                            if self.mode == "normal":
                                self.mode = "insert"
                                self.message = "-- INSERT --"
                                self._set_cursor_shape(beam=True)
                            elif self.mode == "insert":
                                self.mode = "normal"
                                self.message = "EVim - normal mode"
                                self._set_cursor_shape(beam=False)
                            return
                        # Click on LSP indicator
                        if self.lsp_enabled:
                            lsp_col = width - 5
                            if lsp_col <= mx:
                                self.message = f"LSP: {self.lsp_server_cmd[0] if self.lsp_server_cmd else 'none'} | Diagnostics: {len(self.lsp_diagnostics)}"
                                return
                    return
                # Scroll wheel (works in any mode in the editor area)
                if bstate & (curses.BUTTON4_PRESSED if hasattr(curses, 'BUTTON4_PRESSED') else 0):
                    self.scroll_half_up(height)
                    return
                if bstate & (curses.BUTTON5_PRESSED if hasattr(curses, 'BUTTON5_PRESSED') else 0):
                    self.scroll_half_down(height)
                    return
                # Alt+Click — add/remove multi-cursor
                if bstate & curses.BUTTON1_PRESSED and (bstate & curses.BUTTON_ALT if hasattr(curses, 'BUTTON_ALT') else False):
                    tab_h = 1 if self.options.get("tabline") else 0
                    top = max(0, self.cy - height + 4 + tab_h)
                    has_nums = self.options.get("number") or self.options.get("relativenumber")
                    prefix_w = (2 if self.git_diff_lines else 0) + (5 if has_nums else 0)
                    editor_left = min(self.explorer_width, width // 3) if self.explorer_visible else 0
                    target_line = top + my - tab_h
                    target_col = max(0, mx - editor_left - prefix_w + self.scroll_left)
                    if 0 <= target_line < len(self.lines):
                        self.multicursor_add(target_line, target_col)
                    return
                # Click / drag in the editor text area
                if my >= tab_h and my < height - 2:
                    target_line = top + my - tab_h
                    editor_left_off = min(self.explorer_width, width // 3) if self.explorer_visible else 0
                    target_col = max(0, mx - prefix_w - editor_left_off + scroll_left)
                    if 0 <= target_line < len(self.lines):
                        target_col = min(target_col, len(self.lines[target_line]))
                        # Double/Triple-click: word/line selection
                        if bstate & (curses.BUTTON1_CLICKED | curses.BUTTON1_PRESSED):
                            same_pos = (self._last_click_pos == (target_line, target_col))
                            if same_pos and (now - self._last_click_time) < 0.4:
                                if (now - self._triple_click_time) < 0.8 and self.selection:
                                    # Triple click — select entire line
                                    self.selection = (target_line, 0)
                                    self.cy = target_line
                                    self.cx = len(self.lines[target_line])
                                    self.message = "Line selected"
                                    self._last_click_time = 0
                                    self._last_click_pos = (-1, -1)
                                    self._triple_click_time = 0
                                    return
                                # Double click — select word
                                self._triple_click_time = now
                                line = self.lines[target_line]
                                wstart = target_col
                                wend = target_col
                                while wstart > 0 and (line[wstart - 1].isalnum() or line[wstart - 1] == '_'):
                                    wstart -= 1
                                while wend < len(line) and (line[wend].isalnum() or line[wend] == '_'):
                                    wend += 1
                                if wend > wstart:
                                    self.selection = (target_line, wstart)
                                    self.cy = target_line
                                    self.cx = wend
                                    if self.mode not in ("visual", "command"):
                                        self.mode = "normal"
                                    self.message = "Word selected"
                                self._last_click_time = 0
                                self._last_click_pos = (-1, -1)
                                return
                            # Single click — position cursor
                            self._last_click_time = now
                            self._last_click_pos = (target_line, target_col)
                            # If in terminal mode, switch back to normal
                            if self.mode == "terminal":
                                self.mode = "normal"
                                self.message = "EVim - normal mode"
                            # Clear selection on plain click
                            self.selection = None
                            self._mouse_dragging = True
                            self.cy = target_line
                            self.cx = target_col
                        # Drag (button1 held + motion) — visual selection
                        elif bstate & curses.REPORT_MOUSE_POSITION or bstate & curses.BUTTON1_RELEASED:
                            if self._mouse_dragging:
                                if self.selection is None:
                                    self.selection = (self.cy, self.cx)
                                self.cy = target_line
                                self.cx = target_col
                                if bstate & curses.BUTTON1_RELEASED:
                                    self._mouse_dragging = False
                                    sy, sx = self.selection
                                    if sy == self.cy and sx == self.cx:
                                        self.selection = None
            except curses.error:
                pass
            return
        # Ctrl+n - toggle terminal panel (works from any mode except command)
        if ch == 14 and self.mode != "command":
            if self.mode == "terminal":
                self.term_visible = False
                self.mode = "normal"
                self.message = "EVim - normal mode"
                self._set_cursor_shape(beam=False)
            else:
                self.term_toggle()
            return
        # Ctrl+e - toggle file explorer (works from any mode except command)
        if ch == 5 and self.mode != "command":
            if self.mode == "explorer":
                self.explorer_visible = False
                self.mode = "normal"
                self.message = "EVim - normal mode"
            else:
                self.explorer_toggle()
            return
        # Ctrl+m - toggle minimap
        if ch == 13 and self.mode not in ("command", "insert"):
            self.minimap_toggle()
            return
        # F5 - run file
        if ch == curses.KEY_F5:
            self.run_file()
            return
        # F10 - settings menu
        if ch == curses.KEY_F10:
            self.menu_visible = True
            self.menu_cursor = 0
            return
        # F2 - save config
        if ch == curses.KEY_F2 and not self.bindings.get(("normal", "<F2>")):
            self.save_config()
            return
        # Explorer mode input handling
        if self.mode == "explorer":
            self.explorer_handle_key(ch)
            return
        # Diagnostics panel key handling (overrides normal when panel visible)
        if self._diag_panel_visible and self.mode == "normal":
            self.handle_diagnostics_panel_key(ch)
            return
        # Git panel key handling
        if self._git_status_visible and self.mode == "normal":
            self.handle_git_panel_key(ch)
            return
        # Terminal mode input handling — keystrokes go directly to pty
        if self.mode == "terminal":
            if ch in (curses.KEY_EXIT, 27):
                self.term_visible = False
                self.mode = "normal"
                self.message = "EVim - normal mode"
                self._set_cursor_shape(beam=False)
                return
            if ch in (curses.KEY_ENTER, 10, 13):
                self.term_write("\n")
                return
            if ch in (curses.KEY_BACKSPACE, 127, curses.ascii.DEL):
                self.term_write("\x7f")
                return
            if ch == curses.KEY_UP:
                self.term_write("\x1b[A")
                return
            if ch == curses.KEY_DOWN:
                self.term_write("\x1b[B")
                return
            if ch == curses.KEY_LEFT:
                self.term_write("\x1b[D")
                return
            if ch == curses.KEY_RIGHT:
                self.term_write("\x1b[C")
                return
            if ch == curses.KEY_HOME:
                self.term_write("\x1b[H")
                return
            if ch == curses.KEY_END:
                self.term_write("\x1b[F")
                return
            if ch == curses.KEY_DC:  # Delete key
                self.term_write("\x1b[3~")
                return
            if ch == curses.KEY_PPAGE:  # Page Up — scroll terminal
                self.term_scroll = min(self.term_scroll + 5, max(0, len(self.term_lines) - 5))
                return
            if ch == curses.KEY_NPAGE:  # Page Down — scroll terminal
                self.term_scroll = max(0, self.term_scroll - 5)
                return
            # Send control characters and printable chars directly
            if 0 <= ch < 256:
                self.term_write(chr(ch))
                return
            return
        if self.mode == "insert":
            # LSP completion navigation
            if self.lsp_completion_active:
                if ch == 9:  # Tab - next completion
                    self.lsp_completion_idx = (self.lsp_completion_idx + 1) % len(self.lsp_completions)
                    return
                if ch == curses.KEY_UP:
                    self.lsp_completion_idx = (self.lsp_completion_idx - 1) % len(self.lsp_completions)
                    return
                if ch == curses.KEY_DOWN:
                    self.lsp_completion_idx = (self.lsp_completion_idx + 1) % len(self.lsp_completions)
                    return
                if ch in (curses.KEY_ENTER, 10, 13):
                    self.lsp_apply_completion()
                    return
                if ch == 27:  # ESC dismisses completion
                    self.lsp_completion_active = False
                    self.lsp_completions = []
                    self.mode = "normal"
                    self.message = "EVim - normal mode"
                    self._set_cursor_shape(beam=False)
                    return
                # Any other key dismisses completion and processes normally
                self.lsp_completion_active = False
                self.lsp_completions = []
            if ch in (curses.KEY_EXIT, 27):
                self.mode = "normal"
                self.message = "EVim - normal mode"
                self._set_cursor_shape(beam=False)
                return
            if ch in (curses.KEY_BACKSPACE, 127, curses.ascii.DEL):
                self.snapshot()
                self.backspace()
                return
            if ch in (curses.KEY_ENTER, 10, 13):
                self.snapshot()
                self.newline()
                return
            if ch == curses.KEY_DC:
                self.snapshot()
                self.delete_char()
                return
            if ch == curses.KEY_LEFT:
                self.move_left()
                return
            if ch == curses.KEY_RIGHT:
                self.move_right()
                return
            if ch == curses.KEY_UP:
                self.move_up()
                return
            if ch == curses.KEY_DOWN:
                self.move_down()
                return
            if ch == 9:
                if self.lsp_enabled and self.lsp_initialized:
                    self.lsp_completion()
                else:
                    self.do_completion()
                return
            if ch == 19:  # Ctrl+s in insert mode
                self.quick_save()
                return
            if curses.ascii.isprint(ch):
                self.snapshot()
                char = chr(ch)
                if self.syntax_language and self.try_skip_closing(char):
                    self.lsp_did_change()
                    return
                if self.syntax_language and self.try_insert_pair(char):
                    self.lsp_did_change()
                    return
                self.insert_char(char)
                self.lsp_did_change()
                return
            return
        if self.mode == "command":
            if ch in (curses.KEY_ENTER, 10, 13):
                self._isearch_active = False
                self._isearch_matches = []
                self.run_command()
                self.command = ""
                self.mode = "normal"
                return
            if ch in (curses.KEY_BACKSPACE, 127, curses.ascii.DEL):
                self.command = self.command[:-1]
                # Update incremental search
                if self.command.startswith("/") or self.command.startswith("?"):
                    self._isearch_active = True
                    self.isearch_update(self.command[1:])
                return
            if ch == 27:
                self._isearch_active = False
                self._isearch_matches = []
                # Restore cursor to pre-search position
                if hasattr(self, '_isearch_origin'):
                    self.cy, self.cx = self._isearch_origin
                self.mode = "normal"
                self.command = ""
                self.message = "EVim - normal mode"
                return
            # Ctrl+n / Ctrl+p for next/prev match during search
            if ch == 14 and self._isearch_active:  # Ctrl+n
                self.isearch_next()
                return
            if ch == 16 and self._isearch_active:  # Ctrl+p
                self.isearch_prev()
                return
            if 0 <= ch < 256:
                self.command += chr(ch)
                # Incremental search as you type
                if self.command.startswith("/") or self.command.startswith("?"):
                    self._isearch_active = True
                    self._isearch_origin = self._isearch_origin if hasattr(self, '_isearch_origin') and self._isearch_active else (self.cy, self.cx)
                    self.isearch_update(self.command[1:])
            return
        key = self.key_name(ch)
        if self.pending_normal:
            combo = self.pending_normal + key
            self.pending_normal = ""
            if combo == "dd":
                self.snapshot()
                self.delete_line()
                self.last_edit = ("delete_line", ())
                return
            if combo == "dw":
                self.snapshot()
                self.delete_word()
                self.last_edit = ("delete_word", ())
                return
            if combo == "yy":
                self.yank_line()
                return
            if combo == "cw":
                self.snapshot()
                self.change_word()
                return
            if combo == "cs":
                self._surround_pending = "cs"
                self.message = "cs: enter old char..."
                return
            if combo == "ds":
                self._surround_pending = "ds"
                self.message = "ds: enter char to delete..."
                return
            if combo == "vv":
                self.toggle_selection()
                return
            # failed combo, continue processing key normally
        if self.selection and key == "d":
            self.snapshot()
            if self.selection_type == "block":
                self.delete_block_selection()
            else:
                self.delete_selection()
            return
        if self.selection and key == "y":
            if self.selection_type == "block":
                self.yank_block_selection()
            else:
                self.yank_selection()
            return
        if key == "d":
            self.pending_normal = "d"
            return
        if key == "c":
            self.pending_normal = "c"
            return
        if key == "y":
            self.pending_normal = "y"
            return
        binding = self.bindings.get(("normal", key))
        if binding:
            self.call_binding(binding)
            return
        if key == "i":
            self.mode = "insert"
            self.message = "EVim - insert mode"
            self._set_cursor_shape(beam=True)
            self.pending_normal = ""
            return
        if key == ":":
            self.mode = "command"
            self.command = ""
            self.pending_normal = ""
            return
        if key == "h":
            self.move_left()
            self.pending_normal = ""
            return
        if key == "j":
            self.move_down()
            self.pending_normal = ""
            return
        if key == "k":
            self.move_up()
            self.pending_normal = ""
            return
        if key == "l":
            self.move_right()
            self.pending_normal = ""
            return
        if key == "x":
            self.snapshot()
            self.delete_char()
            self.last_edit = ("delete_char", ())
            self.pending_normal = ""
            return
        if key == "p":
            self.snapshot()
            self.paste_after()
            self.pending_normal = ""
            return
        if key == "u":
            self.undo()
            self.pending_normal = ""
            return
        if ch == 18:  # Ctrl+r for redo
            self.redo()
            self.pending_normal = ""
            return
        if key == "n":
            self.find_again(1)
            self.pending_normal = ""
            return
        if key == "N":
            self.find_again(-1)
            self.pending_normal = ""
            return
        if key == "v":
            self.toggle_selection()
            self.pending_normal = ""
            return
        if key == "0":
            self.cx = 0
            self.pending_normal = ""
            return
        if key == "$":
            self.cx = len(self.current_line())
            self.pending_normal = ""
            return
        if key == "G":
            self.jumplist_push()
            self.cy = len(self.lines) - 1
            self.cx = min(self.cx, len(self.current_line()))
            self.pending_normal = ""
            return

        # gg - go to top
        if self.pending_normal == "g" and key == "g":
            self.jumplist_push()
            self.cy = 0
            self.cx = 0
            self.pending_normal = ""
            return
        # gd - go to definition (LSP)
        if self.pending_normal == "g" and key == "d":
            self.pending_normal = ""
            self.lsp_goto_definition()
            return
        # gr - find references (LSP)
        if self.pending_normal == "g" and key == "r":
            self.pending_normal = ""
            self.lsp_references()
            return
        if key == "g":
            self.pending_normal = "g"
            return
        if self.pending_normal == "g":
            self.pending_normal = ""

        # Word motions
        if key == "w":
            self.word_forward()
            return
        if key == "b":
            self.word_backward()
            return
        if key == "e":
            self.word_end()
            return

        # o/O - open line
        if key == "o":
            self.open_line_below()
            return
        if key == "O":
            self.open_line_above()
            return

        # A/I - insert at end/start
        if key == "A":
            self.insert_at_end()
            return
        if key == "I":
            self.insert_at_start()
            return

        # % - bracket match
        if key == "%":
            self.match_bracket()
            return

        # Scroll: Ctrl+d, Ctrl+u, Ctrl+f, Ctrl+b
        if ch == 4:  # Ctrl+d
            height = stdscr.getmaxyx()[0]
            self.scroll_half_down(height)
            return
        if ch == 21:  # Ctrl+u
            height = stdscr.getmaxyx()[0]
            self.scroll_half_up(height)
            return
        if ch == 6:  # Ctrl+f
            height = stdscr.getmaxyx()[0]
            self.scroll_page_down(height)
            return
        if ch == 2:  # Ctrl+b
            height = stdscr.getmaxyx()[0]
            self.scroll_page_up(height)
            return

        # Ctrl+/ - toggle comment (sends 31 on most terminals)
        if ch == 31:
            self.toggle_comment()
            return

        # Ctrl+Up / Ctrl+Down - fast scroll (5 lines)
        if ch == 566 or ch == curses.KEY_SR:  # Ctrl+Up
            self.cy = max(0, self.cy - 5)
            self.cx = min(self.cx, len(self.current_line()))
            return
        if ch == 525 or ch == curses.KEY_SF:  # Ctrl+Down
            self.cy = min(len(self.lines) - 1, self.cy + 5)
            self.cx = min(self.cx, len(self.current_line()))
            return

        # . - dot repeat (replay last edit action keys)
        if key == ".":
            if self.last_edit:
                name, args = self.last_edit
                method = getattr(self, name, None)
                if method:
                    self.snapshot()
                    method(*args)
            return

        # Macros: q to toggle recording, @ to play
        if key == "q":
            if self.macro_recording:
                self.stop_macro()
            else:
                self.pending_normal = "q"
            return
        if self.pending_normal == "q":
            self.start_macro(key)
            self.pending_normal = ""
            return
        if key == "@":
            self.pending_normal = "@"
            return
        if self.pending_normal == "@":
            self.play_macro(key, stdscr)
            self.pending_normal = ""
            return

        # Marks: m to set, ' to jump
        if key == "m":
            self.pending_normal = "m"
            return
        if self.pending_normal == "m":
            self.set_mark(key)
            self.pending_normal = ""
            return
        if key == "'":
            self.pending_normal = "'"
            return
        if self.pending_normal == "'":
            self.goto_mark(key)
            self.pending_normal = ""
            return

        # Registers: " to select register
        if key == '"':
            self.pending_normal = '"'
            return
        if self.pending_normal == '"':
            self.pending_register = key
            self.pending_normal = ""
            return

        # Ctrl+p - fuzzy file finder
        if ch == 16:  # Ctrl+p
            self.fuzzy_find(stdscr)
            return

        # J - join lines
        if key == "J":
            self.snapshot()
            self.join_lines()
            self.last_edit = ("join_lines", ())
            return

        # K - LSP hover info
        if key == "K":
            self.lsp_hover()
            return

        # ~ - toggle case
        if key == "~":
            self.snapshot()
            self.toggle_case()
            return

        # z prefix — folding commands
        if key == "z":
            self.pending_normal = "z"
            return
        if self.pending_normal == "z":
            self.pending_normal = ""
            if key == "a":
                self.fold_toggle()
            elif key == "o":
                self.fold_open()
            elif key == "c":
                self.fold_close()
            elif key == "M":
                self.fold_all()
            elif key == "R":
                self.unfold_all()
            else:
                self.message = f"Unknown fold command: z{key}"
            return

        # Surround pending handlers (set by cs/ds combos above)
        if self._surround_pending == "cs":
            self._surround_pending = ("cs", key)
            self.message = f"cs{key}: enter new char..."
            return
        if isinstance(self._surround_pending, tuple) and self._surround_pending[0] == "cs":
            old_char = self._surround_pending[1]
            self.surround_change(old_char, key)
            self._surround_pending = None
            return
        if self._surround_pending == "ds":
            self.surround_delete(key)
            self._surround_pending = None
            return

        # S in visual mode — surround selection
        if key == "S" and self.selection:
            self._surround_pending = "ys"
            self.message = "S: enter surround char..."
            return
        if self._surround_pending == "ys":
            self.surround_add(key)
            self._surround_pending = None
            return

        # Ctrl+x — command palette (M-x style)
        if ch == 24:  # Ctrl+x
            self.palette_open()
            return

        # Ctrl+y — kill ring paste
        if ch == 25:  # Ctrl+y
            self.kill_ring_yank()
            return

        # Ctrl+s - quick save
        if ch == 19:  # Ctrl+s
            self.quick_save()
            return

        # Ctrl+o - jump back
        if ch == 15:  # Ctrl+o
            self.jumplist_back()
            return

        # Ctrl+i - jump forward (Tab in normal mode)
        if ch == 9:  # Ctrl+i / Tab
            self.jumplist_forward()
            return

        # Ctrl+g - file info
        if ch == 7:  # Ctrl+g
            total = len(self.lines)
            pct = int((self.cy + 1) / total * 100) if total else 0
            fname = self.filepath or "[No Name]"
            mod = " [Modified]" if self.dirty else ""
            self.message = f'"{fname}"{mod} {total} lines --{pct}%-- Ln {self.cy + 1}, Col {self.cx + 1}'
            return

        # Alt key sequences (ESC + key)
        if ch == 27 and self.mode == "normal":
            stdscr.timeout(50)  # Brief wait for Alt sequence
            next_ch = stdscr.getch()
            stdscr.timeout(100)  # Restore timeout
            if next_ch == curses.KEY_UP or next_ch == ord('k'):
                self.snapshot()
                self.move_line_up()
                return
            elif next_ch == curses.KEY_DOWN or next_ch == ord('j'):
                self.snapshot()
                self.move_line_down()
                return
            elif next_ch == ord('d') or next_ch == ord('D'):
                self.snapshot()
                self.duplicate_line()
                return
            elif next_ch == ord('x') or next_ch == ord('X'):
                # Alt+x - command palette (Emacs M-x style)
                self.palette_open()
                return
            elif next_ch == ord('y') or next_ch == ord('Y'):
                # Alt+y - kill ring rotate
                self.kill_ring_rotate()
                return
            elif next_ch == ord('o') or next_ch == ord('O'):
                # Alt+o - symbol outline
                self._build_outline()
                return
            elif next_ch in (curses.KEY_ENTER, 10, 13):
                # Alt+Enter - LSP code actions
                self.lsp_code_action()
                return
            elif next_ch == -1:
                # Just ESC, no follow-up - do nothing in normal mode
                return
            # Unknown Alt combo - ignore
            return

        # Ctrl+v — visual block mode
        if ch == 22:
            self.toggle_visual_block()
            return

        # Ctrl+w — split pane commands
        if ch == 23:
            stdscr.timeout(300)
            next_ch = stdscr.getch()
            stdscr.timeout(100)
            if next_ch >= 0:
                self._handle_split_key(stdscr, next_ch)
            return

        # / and ? for search
        if key == "/":
            self._isearch_origin = (self.cy, self.cx)
            self.mode = "command"
            self.command = "/"
            self.pending_normal = ""
            return
        if key == "?":
            self._isearch_origin = (self.cy, self.cx)
            self.mode = "command"
            self.command = "?"
            self.pending_normal = ""
            return

    def key_name(self, ch):
        if ch == curses.KEY_LEFT:
            return "LEFT"
        if ch == curses.KEY_RIGHT:
            return "RIGHT"
        if ch == curses.KEY_UP:
            return "UP"
        if ch == curses.KEY_DOWN:
            return "DOWN"
        if ch == curses.KEY_F1:
            return "<F1>"
        try:
            return chr(ch)
        except Exception:
            return str(ch)

    def call_binding(self, binding):
        try:
            if callable(binding):
                try:
                    binding(self)
                except TypeError:
                    binding()
        except Exception as exc:
            self.message = f"Binding error: {exc}"

    def current_line(self):
        return self.lines[self.cy]

    def set_cursor(self):
        self.cx = max(0, min(self.cx, len(self.current_line())))
        self.cy = max(0, min(self.cy, len(self.lines) - 1))

    def current_char(self):
        line = self.current_line()
        return line[self.cx] if self.cx < len(line) else ""

    def try_skip_closing(self, char):
        closings = {')': '(', ']': '[', '}': '{', '"': '"', "'": "'"}
        line = self.current_line()
        if char in closings and self.cx < len(line) and line[self.cx] == char:
            self.cx += 1
            return True
        return False

    def try_insert_pair(self, char):
        pairs = {'(': ')', '[': ']', '{': '}', '"': '"', "'": "'"}
        if char not in pairs:
            return False
        line = self.current_line()
        closing = pairs[char]
        self.lines[self.cy] = line[:self.cx] + char + closing + line[self.cx:]
        self.cx += 1
        self.mark_dirty()
        return True

    def move_left(self):
        if self.cx > 0:
            self.cx -= 1
        elif self.cy > 0:
            self.cy -= 1
            self.cx = len(self.current_line())

    def move_right(self):
        if self.cx < len(self.current_line()):
            self.cx += 1
        elif self.cy < len(self.lines) - 1:
            self.cy += 1
            self.cx = 0

    def move_up(self):
        if self.cy > 0:
            self.cy -= 1
            self.cx = min(self.cx, len(self.current_line()))

    def move_down(self):
        if self.cy < len(self.lines) - 1:
            self.cy += 1
            self.cx = min(self.cx, len(self.current_line()))

    def insert_char(self, ch):
        line = self.current_line()
        self.lines[self.cy] = line[:self.cx] + ch + line[self.cx:]
        self.cx += 1
        self.mark_dirty()

    def newline(self):
        line = self.current_line()
        before = line[: self.cx]
        after = line[self.cx :]
        self.lines[self.cy] = before
        self.lines.insert(self.cy + 1, after)
        self.cy += 1
        indent = self.calculate_indent(self.cy - 1)
        self.lines[self.cy] = " " * indent + self.lines[self.cy].lstrip(" ")
        self.cx = indent
        self.mark_dirty()

    def calculate_indent(self, line_no):
        if not self.syntax_language:
            return 0
        if line_no < 0 or line_no >= len(self.lines):
            return 0
        line = self.lines[line_no]
        stripped = line.strip()
        base = len(line) - len(line.lstrip(" "))
        if not stripped:
            return base
        if stripped.endswith(("{", "(", "[", ":")):
            return base + self.options.get("tabsize", 4)
        if self.syntax_language in ("ruby",) and stripped.endswith(("do", "then", "|")):
            return base + self.options.get("tabsize", 4)
        if self.syntax_language == "shell" and stripped.endswith(("then", "do", "else")):
            return base + self.options.get("tabsize", 4)
        return base

    def backspace(self):
        if self.cx > 0:
            line = self.current_line()
            self.lines[self.cy] = line[: self.cx - 1] + line[self.cx :]
            self.cx -= 1
            self.mark_dirty()
        elif self.cy > 0:
            prev = self.lines[self.cy - 1]
            self.cx = len(prev)
            self.lines[self.cy - 1] = prev + self.current_line()
            del self.lines[self.cy]
            self.cy -= 1
            self.mark_dirty()

    def delete_char(self):
        line = self.current_line()
        if self.cx < len(line):
            self.lines[self.cy] = line[: self.cx] + line[self.cx + 1 :]
            self.mark_dirty()
        elif self.cy < len(self.lines) - 1:
            self.lines[self.cy] += self.lines[self.cy + 1]
            del self.lines[self.cy + 1]
            self.mark_dirty()

    def run_command(self):
        command = self.command.strip()
        if not command:
            self.message = ""
            return
        self.run_ex(command)

    def _resolve_option(self, name):
        """Map option aliases to internal names."""
        return OPTION_ALIASES.get(name, name)

    def run_ex(self, command):
        """Execute a single ex command."""
        command = command.strip()
        if command.startswith(":"):
            command = command[1:].strip()
        if not command:
            return

        # Search / replace shortcuts
        if command.startswith("/") or command.startswith("?"):
            self.search_command(command)
            return
        if command.startswith("s/") or command.startswith("%s/"):
            self.replace_command(command)
            return

        # Parse command name and rest
        parts = command.split(None, 1)
        cmd = parts[0]
        rest = parts[1] if len(parts) > 1 else ""

        # set
        if cmd == "set":
            self._ex_set(rest)
            return

        # write
        if cmd in ("w", "write"):
            if rest:
                old_name = self.filepath
                self.filepath = rest
                self.filetype = Path(rest).suffix.lower()
                self.detect_syntax()
                # Update buffer tracking
                buf_key = old_name or "[No Name]"
                if buf_key in self.buffers:
                    del self.buffers[buf_key]
                if buf_key in self.buffer_order:
                    idx = self.buffer_order.index(buf_key)
                    self.buffer_order[idx] = rest
                self.buffers[rest] = self.lines[:]
            self.write_file()
            return

        # quit
        if cmd == "q":
            if self.dirty:
                self.message = "Unsaved changes! Use :q! to force quit."
            else:
                self.should_exit = True
            return
        if cmd == "q!":
            self.should_exit = True
            return
        if cmd == "wq":
            if rest:
                self.filepath = rest
                self.filetype = Path(rest).suffix.lower()
                self.detect_syntax()
            if not self.filepath:
                self.message = "No filename. Use :wq <filename> or :w <filename> first."
                return
            self.write_file()
            self.should_exit = True
            return

        # edit / open buffer
        if cmd in ("e", "edit"):
            if rest:
                self.open_buffer(rest)
            else:
                self.message = "Usage: :e <filename>"
            return

        # buffers
        if cmd in ("bn", "bnext"):
            self.next_buffer()
            return
        if cmd in ("bp", "bprev"):
            self.prev_buffer()
            return
        if cmd in ("ls", "buffers"):
            self.list_buffers()
            return

        # echo
        if cmd == "echo":
            self.message = rest
            return

        # theme / colorscheme
        if cmd in ("theme", "colorscheme"):
            if rest:
                self.set_theme(rest.strip())
            else:
                self.message = f"Current theme: {self.options.get('theme', 'default')}"
            return

        # syntax
        if cmd == "syntax":
            val = rest.strip().lower()
            if val == "on":
                self.options["syntax"] = True
                self.detect_syntax()
                self.message = "Syntax highlighting enabled"
            elif val == "off":
                self.options["syntax"] = False
                self.syntax_language = None
                self.message = "Syntax highlighting disabled"
            else:
                self.message = "Usage: :syntax on|off"
            return

        # help
        if cmd == "help":
            self.mode = "overlay"
            self.show_welcome = False
            self.message = "EVim help"
            return

        # map commands
        if cmd == "map":
            mparts = rest.split(None, 2)
            if len(mparts) >= 3:
                mode, key, action = mparts[0], mparts[1], mparts[2]
                self.register_key(mode, key,
                    lambda e, a=action: e.run_mapped_action(a))
                self.message = f"Mapped [{mode}] {key} -> {action}"
            else:
                self.message = "Usage: :map <mode> <key> <action>"
            return
        if cmd in ("nmap", "nnoremap"):
            mparts = rest.split(None, 1)
            if len(mparts) >= 2:
                key, action = mparts[0], mparts[1]
                self.register_key("normal", key,
                    lambda e, a=action: e.run_mapped_action(a))
                self.message = f"Mapped [normal] {key} -> {action}"
            else:
                self.message = f"Usage: :{cmd} <key> <action>"
            return
        if cmd in ("imap", "inoremap"):
            mparts = rest.split(None, 1)
            if len(mparts) >= 2:
                key, action = mparts[0], mparts[1]
                self.register_key("insert", key,
                    lambda e, a=action: e.run_mapped_action(a))
                self.message = f"Mapped [insert] {key} -> {action}"
            else:
                self.message = f"Usage: :{cmd} <key> <action>"
            return
        if cmd in ("vmap", "vnoremap"):
            mparts = rest.split(None, 1)
            if len(mparts) >= 2:
                key, action = mparts[0], mparts[1]
                self.register_key("visual", key,
                    lambda e, a=action: e.run_mapped_action(a))
                self.message = f"Mapped [visual] {key} -> {action}"
            else:
                self.message = f"Usage: :{cmd} <key> <action>"
            return

        # python / py
        if cmd in ("python", "py"):
            if rest:
                self.run_python(rest)
            else:
                self.message = "Usage: :python <code>"
            return

        # source
        if cmd == "source":
            if rest:
                path = Path(rest.strip())
                if path.exists():
                    content = path.read_text(encoding="utf-8")
                    try:
                        exec(compile(content, str(path), "exec"),
                             {"editor": self, "__builtins__": __builtins__})
                        self.message = f"Sourced {path.name}"
                    except Exception as exc:
                        self.message = f"Source error: {exc}"
                else:
                    self.message = f"File not found: {rest}"
            else:
                self.message = "Usage: :source <file>"
            return

        # Jump to line number (:42)
        try:
            lineno = int(cmd)
            self.cy = max(0, min(lineno - 1, len(self.lines) - 1))
            self.cx = 0
            self.message = f"Line {self.cy + 1}"
            return
        except ValueError:
            pass

        # ── Plugin commands ──
        if cmd in ("PluginLoad", "pluginload", "plugin-load"):
            if rest:
                if self.plugin_load_file(rest.strip()):
                    self.message = f"Plugin loaded: {rest.strip()}"
            else:
                n = self.plugin_load_all()
                self.message = f"Loaded {n} plugin(s) from plugin dirs"
            return
        if cmd in ("PluginList", "pluginlist", "plugin-list", "plugins"):
            plist = self.plugin_list()
            if plist:
                lines = [f"  {'✓' if e else '✗'} {n} v{v} — {d}" for n, v, e, d in plist]
                self.message = f"{len(plist)} plugin(s): " + "; ".join(
                    f"{n} v{v}" for n, v, e, d in plist)
            else:
                self.message = "No plugins loaded"
            return
        if cmd in ("PluginDisable", "plugindisable", "plugin-disable"):
            if rest:
                self.plugin_disable(rest.strip())
            else:
                self.message = "Usage: :PluginDisable <name>"
            return
        if cmd in ("PluginEnable", "pluginenable", "plugin-enable"):
            if rest:
                self.plugin_enable(rest.strip())
            else:
                self.message = "Usage: :PluginEnable <name>"
            return

        # ── File Explorer / Minimap ──
        if cmd == "explorer":
            self.explorer_toggle()
            return
        if cmd == "minimap":
            self.minimap_toggle()
            return
        if cmd == "run":
            self.run_file()
            return
        if cmd == "lsp":
            arg = rest.strip().lower()
            if arg == "stop":
                self.lsp_stop()
            elif arg == "restart":
                self.lsp_stop()
                self.lsp_start()
            elif arg == "status":
                if self.lsp_enabled:
                    srv = self.lsp_server_cmd[0] if self.lsp_server_cmd else "?"
                    diag_count = len(self.lsp_diagnostics)
                    self.message = f"LSP: {srv} | {diag_count} diagnostics"
                else:
                    self.message = "LSP: not running"
            else:
                self.lsp_start()
            return

        # ── QoL: cd, pwd ──
        if cmd == "cd":
            target = rest.strip() if rest else str(Path.home())
            target = os.path.expanduser(target)
            try:
                os.chdir(target)
                self.message = f"cd {os.getcwd()}"
            except Exception as exc:
                self.message = f"cd failed: {exc}"
            return
        if cmd == "pwd":
            self.message = os.getcwd()
            return

        # ── QoL: shell command ──
        if cmd == "!" or command.startswith("!"):
            shell_cmd = (rest if cmd == "!" else command[1:]).strip()
            if not shell_cmd:
                self.message = "Usage: :! <command>"
                return
            try:
                result = subprocess.run(shell_cmd, shell=True, capture_output=True,
                                        text=True, timeout=10)
                out = result.stdout.strip() or result.stderr.strip()
                self.message = out[:200] if out else f"Exit {result.returncode}"
            except subprocess.TimeoutExpired:
                self.message = "Command timed out (10s)"
            except Exception as exc:
                self.message = f"Shell error: {exc}"
            return

        # ── QoL: sort ──
        if cmd == "sort":
            if self.selection:
                sy, sx = self.selection
                ey = self.cy
                if sy > ey:
                    sy, ey = ey, sy
                self.snapshot()
                self.lines[sy:ey + 1] = sorted(self.lines[sy:ey + 1])
                self.selection = None
                self.message = f"Sorted lines {sy + 1}-{ey + 1}"
            else:
                self.snapshot()
                self.lines.sort()
                self.message = f"Sorted all {len(self.lines)} lines"
            self.dirty = True
            return

        # ── QoL: nohlsearch ──
        if cmd in ("noh", "nohlsearch"):
            self.last_search = ""
            self.message = "Search cleared"
            return

        # ── QoL: registers / marks display ──
        if cmd in ("reg", "registers"):
            if self.registers:
                lines = [f'  "{k}: {v[:40]}' for k, v in self.registers.items()]
                self.message = " | ".join(f'"{k}:{v[:20]}' for k, v in self.registers.items())
            else:
                self.message = "No registers set"
            return
        if cmd == "marks":
            if self.marks:
                self.message = " | ".join(f"'{k}:{y+1},{x}" for k, (y, x) in self.marks.items())
            else:
                self.message = "No marks set"
            return

        # ── QoL: only (close all other buffers) ──
        if cmd == "only":
            if self.filepath:
                self.buffers = {self.filepath: self.lines[:]}
                self.buffer_order = [self.filepath]
                self.current_buffer_idx = 0
                self.message = "Closed other buffers"
            return

        # ── Settings menu ──
        if cmd in ("menu", "settings"):
            self.menu_visible = True
            self.menu_cursor = 0
            return

        # ── Save config ──
        if cmd in ("savecfg", "saveconfig", "cfgsave"):
            self.save_config()
            return

        # ── Error lens toggle ──
        if cmd == "errorlens":
            self.options["error_lens"] = not self.options.get("error_lens", True)
            state = "ON" if self.options["error_lens"] else "OFF"
            self.message = f"Error Lens: {state}"
            return

        # ── Move line ──
        if cmd == "moveup":
            self.snapshot()
            self.move_line_up()
            return
        if cmd == "movedown":
            self.snapshot()
            self.move_line_down()
            return

        # ── Duplicate line ──
        if cmd in ("dup", "duplicate"):
            self.snapshot()
            self.duplicate_line()
            return

        # ── Toggle features ──
        if cmd == "tabline":
            self.options["tabline"] = not self.options.get("tabline", True)
            state = "ON" if self.options["tabline"] else "OFF"
            self.message = f"Tab line: {state}"
            return
        if cmd == "brackethl":
            self.options["bracket_highlight"] = not self.options.get("bracket_highlight", True)
            state = "ON" if self.options["bracket_highlight"] else "OFF"
            self.message = f"Bracket highlight: {state}"
            return
        if cmd == "wordhl":
            self.options["word_highlight"] = not self.options.get("word_highlight", False)
            state = "ON" if self.options["word_highlight"] else "OFF"
            self.message = f"Word highlight: {state}"
            return
        if cmd == "autosave":
            self.options["autosave"] = not self.options.get("autosave", False)
            state = "ON" if self.options["autosave"] else "OFF"
            self.message = f"Auto save: {state}"
            return

        # ── Folding ──
        if cmd in ("fold", "za"):
            self.fold_toggle()
            return
        if cmd in ("foldall", "zM"):
            self.fold_all()
            return
        if cmd in ("unfoldall", "zR"):
            self.unfold_all()
            return

        # ── Command palette ──
        if cmd in ("palette", "commands"):
            self.palette_open()
            return

        # ── Grep ──
        if cmd in ("grep", "rg"):
            if rest:
                self.project_grep(rest)
            else:
                self.message = "Usage: :grep <pattern>"
            return

        # ── Symbol outline ──
        if cmd in ("outline", "symbols"):
            self._build_outline()
            return

        # ── Recent files ──
        if cmd in ("recent", "oldfiles"):
            self._show_recent_files()
            return

        # ── Kill ring ──
        if cmd == "killring":
            if self.kill_ring:
                entries = [f"[{i+1}] {t[:40]}" for i, t in enumerate(self.kill_ring[:10])]
                self.message = " | ".join(entries)
            else:
                self.message = "Kill ring empty"
            return

        # ── Session ──
        if cmd in ("mksession", "mks", "savesession"):
            self.session_save()
            return
        if cmd in ("restoresession", "ressession", "loadsession"):
            self.session_restore()
            return

        # ── Diagnostics panel ──
        if cmd in ("diagnostics", "diag"):
            self.toggle_diagnostics_panel()
            return

        # ── Git integration ──
        if cmd == "git":
            subcmd = rest.strip()
            if not subcmd:
                self.message = "Usage: :git <status|diff|log|add|commit|push|pull|branch>"
                return
            parts2 = subcmd.split(None, 1)
            args2 = parts2[1] if len(parts2) > 1 else ""
            self.git_command(parts2[0], args2)
            return

        # ── Remote editing ──
        if cmd in ("scp", "remote"):
            if rest:
                self.open_remote(rest.strip())
            else:
                self.message = "Usage: :scp user@host:/path/to/file"
            return
        if cmd in ("wpush", "pushremote"):
            self.push_remote()
            return

        # ── Multi-cursor ──
        if cmd in ("clearcursors", "nocursor"):
            self.multicursor_clear()
            return

        # ── Inlay hints ──
        if cmd in ("inlayhints", "inlay"):
            self.options["inlay_hints"] = not self.options.get("inlay_hints", True)
            state = "ON" if self.options["inlay_hints"] else "OFF"
            self.message = f"Inlay hints: {state}"
            if self.options["inlay_hints"]:
                self.lsp_request_inlay_hints()
            return

        # ── Split panes ──
        if cmd in ("vsplit", "vsp"):
            self.split_vertical()
            return
        if cmd in ("split", "sp"):
            self.split_horizontal()
            return
        if cmd == "close":
            self.split_close()
            return

        self.message = f"Unknown command: {cmd}"

    def _ex_set(self, rest):
        """Handle :set commands."""
        if not rest:
            self.message = f"Options: {self.options}"
            return
        # set option=value
        if "=" in rest:
            name, _, val = rest.partition("=")
            name = name.strip()
            val = val.strip()
            mapped = self._resolve_option(name)
            try:
                val = int(val)
            except ValueError:
                try:
                    val = float(val)
                except ValueError:
                    pass
            self.options[mapped] = val
            if mapped == "theme":
                self.set_theme(str(val))
                return
            self.message = f"{name}={val}"
            return
        parts = rest.split()
        name = parts[0]
        # set nooption
        if name.startswith("no"):
            canon = name[2:]
            mapped = self._resolve_option(canon)
            self.options[mapped] = False
            self.message = f"{canon} disabled"
            return
        mapped = self._resolve_option(name)
        # set option value  (e.g. set theme matrix_code, set tabstop 4)
        if len(parts) >= 2:
            val = parts[1]
            try:
                val = int(val)
            except ValueError:
                try:
                    val = float(val)
                except ValueError:
                    pass
            self.options[mapped] = val
            if mapped == "theme":
                self.set_theme(str(val))
                return
            self.message = f"{name}={val}"
            return
        # set option (boolean toggle on)
        self.options[mapped] = True
        self.message = f"{name} enabled"

    def search_command(self, command):
        if len(command) < 2:
            self.message = "Use /pattern or ?pattern"
            return
        direction = 1 if command[0] == "/" else -1
        pattern = command[1:]
        if not pattern:
            self.message = "Empty search pattern"
            return
        self.last_search = pattern
        self.search_direction = direction
        found = self.find_pattern(pattern, direction)
        if found:
            self.move_to_search(found)
            self.message = f"Found '{pattern}'"
        else:
            self.message = f"Pattern not found: {pattern}"

    def open_help(self):
        self.mode = "overlay"
        self.message = "EVim help: press any key"

    def snapshot(self):
        self.history.append((list(self.lines), self.cx, self.cy))
        if len(self.history) > 50:
            self.history.pop(0)

    def mark_dirty(self):
        self.dirty = True

    def undo(self):
        if not self.history:
            self.message = "Nothing to undo"
            return
        self.redo_stack.append((list(self.lines), self.cx, self.cy))  # Save for redo
        self.lines, self.cx, self.cy = self.history.pop()
        self.message = "Undo"
        self.set_cursor()

    def redo(self):
        if not self.redo_stack:
            self.message = "Nothing to redo"
            return
        self.history.append((list(self.lines), self.cx, self.cy))  # Save for undo
        self.lines, self.cx, self.cy = self.redo_stack.pop()
        self.message = "Redo"
        self.set_cursor()

    def delete_line(self):
        if not self.lines:
            return
        killed = self.lines[self.cy]
        self.kill_ring_push(killed)
        del self.lines[self.cy]
        if not self.lines:
            self.lines = [""]
            self.cy = 0
            self.cx = 0
        else:
            self.cy = min(self.cy, len(self.lines) - 1)
            self.cx = min(self.cx, len(self.current_line()))
        self.dirty = True
        self.message = "Deleted line"

    def delete_word(self):
        line = self.current_line()
        if self.cx >= len(line):
            self.delete_char()
            return
        end = self.cx
        while end < len(line) and not line[end].isspace():
            end += 1
        self.lines[self.cy] = line[: self.cx] + line[end:]
        self.dirty = True
        self.message = "Deleted word"

    def change_word(self):
        self.delete_word()
        self.mode = "insert"
        self._set_cursor_shape(beam=True)
        self.message = "Change word"

    def yank_line(self):
        text = self.current_line() + "\n"
        self.yank_to_register(text)
        self.message = "Yanked line"

    def paste_after(self):
        text = self.paste_from_register()
        if not text:
            self.message = "Nothing to paste"
            return
        if text.endswith("\n"):
            self.lines.insert(self.cy + 1, text[:-1])
            self.cy += 1
            self.cx = 0
        else:
            line = self.current_line()
            self.lines[self.cy] = line[: self.cx] + text + line[self.cx :]
            self.cx += len(text)
        self.dirty = True
        self.message = "Pasted"

    def toggle_selection(self):
        if self.selection is None:
            self.selection = (self.cy, self.cx)
            self.message = "Visual selection started"
        else:
            self.selection = None
            self.message = "Visual selection cleared"

    def yank_selection(self):
        if self.selection is None:
            self.message = "No selection"
            return
        sy, sx = self.selection
        ey, ex = self.cy, self.cx
        if sy > ey or (sy == ey and sx > ex):
            sy, sx, ey, ex = ey, ex, sy, sx
        lines = self.lines[sy:ey+1]
        if sy == ey:
            copied = lines[0][sx:ex]
        else:
            copied = lines[0][sx:] + "\n"
            for mid in lines[1:-1]:
                copied += mid + "\n"
            copied += lines[-1][:ex]
        self.yank_to_register(copied)
        self.selection = None
        self.message = "Yanked selection"

    def delete_selection(self):
        if self.selection is None:
            self.message = "No selection"
            return
        sy, sx = self.selection
        ey, ex = self.cy, self.cx
        if sy > ey or (sy == ey and sx > ex):
            sy, sx, ey, ex = ey, ex, sy, sx
        if sy == ey:
            line = self.lines[sy]
            self.lines[sy] = line[:sx] + line[ex:]
        else:
            first = self.lines[sy][:sx]
            last = self.lines[ey][ex:]
            self.lines[sy:ey + 1] = [first + last]
        self.cy = sy
        self.cx = sx
        self.selection = None
        self.dirty = True
        self.message = "Deleted selection"

    # ── Word motions ──

    def word_forward(self):
        line = self.current_line()
        if self.cx >= len(line):
            if self.cy < len(self.lines) - 1:
                self.cy += 1
                self.cx = 0
                line = self.current_line()
                while self.cx < len(line) and line[self.cx].isspace():
                    self.cx += 1
            return
        pos = self.cx
        if pos < len(line) and (line[pos].isalnum() or line[pos] == '_'):
            while pos < len(line) and (line[pos].isalnum() or line[pos] == '_'):
                pos += 1
        elif pos < len(line) and not line[pos].isspace():
            while pos < len(line) and not line[pos].isspace() and not (line[pos].isalnum() or line[pos] == '_'):
                pos += 1
        while pos < len(line) and line[pos].isspace():
            pos += 1
        if pos >= len(line) and self.cy < len(self.lines) - 1:
            self.cy += 1
            self.cx = 0
            line = self.current_line()
            while self.cx < len(line) and line[self.cx].isspace():
                self.cx += 1
        else:
            self.cx = pos

    def word_backward(self):
        line = self.current_line()
        if self.cx <= 0:
            if self.cy > 0:
                self.cy -= 1
                self.cx = len(self.current_line())
                line = self.current_line()
            else:
                return
        pos = self.cx - 1
        while pos > 0 and line[pos].isspace():
            pos -= 1
        if pos >= 0 and (line[pos].isalnum() or line[pos] == '_'):
            while pos > 0 and (line[pos - 1].isalnum() or line[pos - 1] == '_'):
                pos -= 1
        elif pos >= 0 and not line[pos].isspace():
            while pos > 0 and not line[pos - 1].isspace() and not (line[pos - 1].isalnum() or line[pos - 1] == '_'):
                pos -= 1
        self.cx = max(0, pos)

    def word_end(self):
        line = self.current_line()
        pos = self.cx + 1
        if pos >= len(line):
            if self.cy < len(self.lines) - 1:
                self.cy += 1
                line = self.current_line()
                pos = 0
            else:
                return
        while pos < len(line) and line[pos].isspace():
            pos += 1
        if pos < len(line) and (line[pos].isalnum() or line[pos] == '_'):
            while pos < len(line) - 1 and (line[pos + 1].isalnum() or line[pos + 1] == '_'):
                pos += 1
        elif pos < len(line):
            while pos < len(line) - 1 and not line[pos + 1].isspace() and not (line[pos + 1].isalnum() or line[pos + 1] == '_'):
                pos += 1
        self.cx = min(pos, len(line))

    # ── Open line ──

    def open_line_below(self):
        self.snapshot()
        indent = len(self.current_line()) - len(self.current_line().lstrip(' '))
        self.lines.insert(self.cy + 1, " " * indent)
        self.cy += 1
        self.cx = indent
        self.mode = "insert"
        self._set_cursor_shape(beam=True)
        self.mark_dirty()
        self.message = "EVim - insert mode"

    def open_line_above(self):
        self.snapshot()
        indent = len(self.current_line()) - len(self.current_line().lstrip(' '))
        self.lines.insert(self.cy, " " * indent)
        self.cx = indent
        self.mode = "insert"
        self._set_cursor_shape(beam=True)
        self.mark_dirty()
        self.message = "EVim - insert mode"

    # ── Insert at start/end ──

    def insert_at_end(self):
        self.cx = len(self.current_line())
        self.mode = "insert"
        self._set_cursor_shape(beam=True)
        self.message = "EVim - insert mode"

    def insert_at_start(self):
        line = self.current_line()
        self.cx = len(line) - len(line.lstrip())
        self.mode = "insert"
        self._set_cursor_shape(beam=True)
        self.message = "EVim - insert mode"

    # ── Match bracket ──

    def match_bracket(self):
        line = self.current_line()
        if self.cx >= len(line):
            return
        ch = line[self.cx]
        pairs = {'(': ')', ')': '(', '[': ']', ']': '[', '{': '}', '}': '{'}
        if ch not in pairs:
            for i, c in enumerate(line[self.cx:]):
                if c in pairs:
                    self.cx += i
                    ch = c
                    break
            else:
                return
        target = pairs[ch]
        forward = ch in ('(', '[', '{')
        depth = 0
        if forward:
            for row in range(self.cy, len(self.lines)):
                start = self.cx + 1 if row == self.cy else 0
                for col in range(start, len(self.lines[row])):
                    c = self.lines[row][col]
                    if c == ch:
                        depth += 1
                    elif c == target:
                        if depth == 0:
                            self.cy, self.cx = row, col
                            return
                        depth -= 1
        else:
            for row in range(self.cy, -1, -1):
                end = self.cx - 1 if row == self.cy else len(self.lines[row]) - 1
                for col in range(end, -1, -1):
                    c = self.lines[row][col]
                    if c == ch:
                        depth += 1
                    elif c == target:
                        if depth == 0:
                            self.cy, self.cx = row, col
                            return
                        depth -= 1

    # ── Scroll commands ──

    def scroll_half_down(self, height):
        half = max(1, (height - 2) // 2)
        self.cy = min(self.cy + half, len(self.lines) - 1)
        self.cx = min(self.cx, len(self.current_line()))

    def scroll_half_up(self, height):
        half = max(1, (height - 2) // 2)
        self.cy = max(self.cy - half, 0)
        self.cx = min(self.cx, len(self.current_line()))

    def scroll_page_down(self, height):
        page = max(1, height - 3)
        self.cy = min(self.cy + page, len(self.lines) - 1)
        self.cx = min(self.cx, len(self.current_line()))

    def scroll_page_up(self, height):
        page = max(1, height - 3)
        self.cy = max(self.cy - page, 0)
        self.cx = min(self.cx, len(self.current_line()))

    # ── Line commenting ──

    def toggle_comment(self):
        comment_map = {
            "c": "// ", "cpp": "// ", "csharp": "// ", "rust": "// ",
            "java": "// ", "go": "// ", "javascript": "// ", "typescript": "// ",
            "swift": "// ", "kotlin": "// ", "scala": "// ",
            "python": "# ", "ruby": "# ", "perl": "# ", "shell": "# ", "php": "// ",
            "lua": "-- ", "fortran": "! ", "pascal": "// ",
            "assembly": "; ",
        }
        prefix = comment_map.get(self.syntax_language, "# ")
        self.snapshot()
        line = self.current_line()
        stripped = line.lstrip()
        if stripped.startswith(prefix):
            indent = len(line) - len(stripped)
            self.lines[self.cy] = line[:indent] + stripped[len(prefix):]
            self.message = "Uncommented"
        else:
            indent = len(line) - len(stripped)
            self.lines[self.cy] = line[:indent] + prefix + stripped
            self.message = "Commented"
        self.mark_dirty()

    # ── Macros ──

    def start_macro(self, reg):
        self.macro_recording = reg
        self.macro_keys = []
        self.message = f"Recording @{reg}..."

    def stop_macro(self):
        if self.macro_recording:
            self.macros[self.macro_recording] = self.macro_keys[:]
            self.message = f"Recorded @{self.macro_recording} ({len(self.macro_keys)} keys)"
            self.macro_recording = None
            self.macro_keys = []

    def play_macro(self, reg, stdscr):
        if not hasattr(self, '_macro_depth'):
            self._macro_depth = 0
        if self._macro_depth > 100:
            self.message = "Macro recursion limit reached"
            return
        keys = self.macros.get(reg)
        if not keys:
            self.message = f"Empty macro @{reg}"
            return
        self._macro_depth += 1
        self.macro_playing = True
        for k in keys:
            self._inject_key = k
            self.handle_key(stdscr)
        self._macro_depth -= 1
        if self._macro_depth == 0:
            self.macro_playing = False
        self._inject_key = None
        self.message = f"Played @{reg}"

    # ── Marks ──

    def set_mark(self, ch):
        self.marks[ch] = (self.cy, self.cx)
        self.message = f"Mark '{ch}' set"

    def goto_mark(self, ch):
        if ch in self.marks:
            self.cy, self.cx = self.marks[ch]
            self.set_cursor()
            self.message = f"Jump to mark '{ch}'"
        else:
            self.message = f"Mark '{ch}' not set"

    # ── Registers ──

    def get_register(self):
        reg = self.pending_register or '"'
        self.pending_register = None
        return reg

    def yank_to_register(self, text):
        reg = self.get_register()
        self.registers[reg] = text
        self.clipboard = text

    def paste_from_register(self):
        reg = self.get_register()
        text = self.registers.get(reg, self.clipboard)
        return text

    # ── Git gutter ──

    def update_git_gutter(self):
        self.git_diff_lines = {}
        if not self.filepath:
            return
        try:
            result = subprocess.run(
                ["git", "diff", "--unified=0", "--no-color", "--", self.filepath],
                capture_output=True, text=True, timeout=2, cwd=str(Path(self.filepath).resolve().parent)
            )
            if result.returncode != 0:
                return
            for m in re.finditer(r'@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@', result.stdout):
                start = int(m.group(1))
                count = int(m.group(2)) if m.group(2) else 1
                if count == 0:
                    self.git_diff_lines[start - 1] = 'deleted'
                else:
                    for i in range(count):
                        self.git_diff_lines[start - 1 + i] = 'added'
        except Exception:
            pass

    # ── Persistent undo ──

    def save_undo_history(self):
        if not self.filepath:
            return
        undo_dir = Path.home() / ".evim_undo"
        undo_dir.mkdir(exist_ok=True)
        safe = re.sub(r'[^a-zA-Z0-9_.-]', '_', str(Path(self.filepath).resolve()))
        path = undo_dir / safe
        data = {"history": [(l, cx, cy) for l, cx, cy in self.history[-20:]]}
        try:
            path.write_text(json.dumps(data), encoding="utf-8")
        except Exception:
            pass

    def load_undo_history(self):
        if not self.filepath:
            return
        undo_dir = Path.home() / ".evim_undo"
        safe = re.sub(r'[^a-zA-Z0-9_.-]', '_', str(Path(self.filepath).resolve()))
        path = undo_dir / safe
        if not path.exists():
            return
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
            for item in data.get("history", []):
                lines, cx, cy = item
                self.history.append((lines, cx, cy))
        except Exception:
            pass

    # ── Fuzzy file finder ──

    def fuzzy_find(self, stdscr):
        query = ""
        selected = 0
        # Scan files once before the input loop
        try:
            all_files = sorted(
                str(p) for p in Path('.').rglob('*')
                if p.is_file() and not any(part.startswith('.') for part in p.parts)
            )
        except Exception:
            all_files = []
        while True:
            height, width = stdscr.getmaxyx()
            stdscr.erase()
            stdscr.addstr(0, 0, f"Find file: {query}_"[:width-1], curses.A_BOLD)
            try:
                if query:
                    ql = query.lower()
                    scored = []
                    for f in all_files:
                        fl = f.lower()
                        if ql in fl:
                            scored.append((fl.index(ql), f))
                    scored.sort()
                    files = [s[1] for s in scored]
                else:
                    files = all_files
                files = files[:height - 3]
            except Exception:
                files = []
            selected = min(selected, max(0, len(files) - 1))
            for i, f in enumerate(files):
                attr = curses.A_REVERSE if i == selected else curses.A_NORMAL
                try:
                    stdscr.addstr(i + 2, 2, f[:width - 4], attr)
                except curses.error:
                    pass
            curses.doupdate()
            ch = stdscr.getch()
            if ch in (27,):
                return
            if ch in (curses.KEY_ENTER, 10, 13):
                if files:
                    self.open_buffer(files[selected])
                return
            if ch in (curses.KEY_BACKSPACE, 127, curses.ascii.DEL):
                query = query[:-1]
            elif ch == curses.KEY_UP:
                selected = max(0, selected - 1)
            elif ch == curses.KEY_DOWN:
                selected += 1
            elif 0 <= ch < 256 and curses.ascii.isprint(ch):
                query += chr(ch)

    # ── LSP (Language Server Protocol) ──

    LSP_SERVERS = {
        "python": ["pyright-langserver", "--stdio"],
        "javascript": ["typescript-language-server", "--stdio"],
        "typescript": ["typescript-language-server", "--stdio"],
        "c": ["clangd"],
        "cpp": ["clangd"],
        "rust": ["rust-analyzer"],
        "go": ["gopls"],
        "lua": ["lua-language-server"],
        "java": ["jdtls"],
        "ruby": ["solargraph", "stdio"],
        "php": ["phpactor", "language-server"],
        "csharp": ["omnisharp", "--languageserver"],
        "zig": ["zls"],
        "dart": ["dart", "language-server"],
        "haskell": ["haskell-language-server-wrapper", "--lsp"],
        "elixir": ["elixir-ls"],
        "kotlin": ["kotlin-language-server"],
        "scala": ["metals"],
        "swift": ["sourcekit-lsp"],
        "html": ["vscode-html-language-server", "--stdio"],
        "css": ["vscode-css-language-server", "--stdio"],
        "json": ["vscode-json-language-server", "--stdio"],
        "yaml": ["yaml-language-server", "--stdio"],
        "vue": ["vue-language-server", "--stdio"],
        "svelte": ["svelteserver", "--stdio"],
        "nim": ["nimlangserver"],
        "ocaml": ["ocamllsp"],
        "clojure": ["clojure-lsp"],
        "julia": ["julia", "--startup-file=no", "-e", "using LanguageServer; runserver()"],
        "terraform": ["terraform-ls", "serve"],
    }

    def lsp_start(self):
        """Start the LSP server for the current language."""
        lang = self.syntax_language
        if not lang:
            self.message = "No language detected for LSP"
            return
        cmd = self.LSP_SERVERS.get(lang)
        if not cmd:
            self.message = f"No LSP server configured for {lang}"
            return
        # Check if server binary exists
        import shutil
        if not shutil.which(cmd[0]):
            self.message = f"LSP server not found: {cmd[0]} (install it first)"
            return
        try:
            self.lsp_process = subprocess.Popen(
                cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                stderr=subprocess.PIPE, bufsize=0
            )
            self.lsp_server_cmd = cmd
            self.lsp_request_id = 0
            self.lsp_initialized = False
            self.lsp_enabled = True
            # Start reader thread
            t = threading.Thread(target=self._lsp_reader_loop, daemon=True)
            t.start()
            # Send initialize request
            root_uri = f"file://{os.path.abspath('.')}"
            self._lsp_send_request("initialize", {
                "processId": os.getpid(),
                "rootUri": root_uri,
                "capabilities": {
                    "textDocument": {
                        "completion": {"completionItem": {"snippetSupport": False}},
                        "hover": {"contentFormat": ["plaintext"]},
                        "publishDiagnostics": {"relatedInformation": True},
                        "definition": {},
                        "codeAction": {"dynamicRegistration": False},
                        "inlayHint": {"dynamicRegistration": False},
                    }
                },
            })
            self.message = f"LSP: starting {cmd[0]}..."
        except Exception as exc:
            self.message = f"LSP start error: {exc}"
            self.lsp_enabled = False

    def lsp_stop(self):
        """Stop the LSP server."""
        if self.lsp_process:
            try:
                self._lsp_send_request("shutdown", {})
                self._lsp_send_notification("exit", None)
                self.lsp_process.terminate()
                self.lsp_process.wait(timeout=3)
            except Exception:
                if self.lsp_process:
                    self.lsp_process.kill()
            # Close pipes to avoid resource leaks
            for pipe in (self.lsp_process.stdin, self.lsp_process.stdout, self.lsp_process.stderr):
                if pipe:
                    try:
                        pipe.close()
                    except Exception:
                        pass
            self.lsp_process = None
        self.lsp_enabled = False
        self.lsp_initialized = False
        self.lsp_diagnostics = []
        self.lsp_hover_text = None
        self.lsp_completions = []
        self.lsp_completion_active = False
        self.message = "LSP stopped"

    def _lsp_send_request(self, method, params):
        """Send a JSON-RPC request to the LSP server."""
        if not self.lsp_process or not self.lsp_process.stdin:
            return -1
        self.lsp_request_id += 1
        rid = self.lsp_request_id
        body = json.dumps({"jsonrpc": "2.0", "id": rid, "method": method, "params": params})
        msg = f"Content-Length: {len(body)}\r\n\r\n{body}"
        try:
            self.lsp_process.stdin.write(msg.encode("utf-8"))
            self.lsp_process.stdin.flush()
        except (BrokenPipeError, OSError):
            self.lsp_enabled = False
        return rid

    def _lsp_send_notification(self, method, params):
        """Send a JSON-RPC notification (no id)."""
        if not self.lsp_process or not self.lsp_process.stdin:
            return
        body = json.dumps({"jsonrpc": "2.0", "method": method, "params": params})
        msg = f"Content-Length: {len(body)}\r\n\r\n{body}"
        try:
            self.lsp_process.stdin.write(msg.encode("utf-8"))
            self.lsp_process.stdin.flush()
        except (BrokenPipeError, OSError):
            self.lsp_enabled = False

    def _lsp_reader_loop(self):
        """Background thread: read LSP server stdout and dispatch responses."""
        buf = b""
        while self.lsp_process and self.lsp_process.poll() is None:
            try:
                chunk = self.lsp_process.stdout.read(1)
                if not chunk:
                    break
                buf += chunk
                # Parse Content-Length header
                while b"\r\n\r\n" in buf:
                    header_end = buf.index(b"\r\n\r\n")
                    header = buf[:header_end].decode("utf-8", errors="replace")
                    content_length = 0
                    for line in header.split("\r\n"):
                        if line.lower().startswith("content-length:"):
                            content_length = int(line.split(":")[1].strip())
                    body_start = header_end + 4
                    if len(buf) < body_start + content_length:
                        break  # Wait for more data
                    body = buf[body_start:body_start + content_length]
                    buf = buf[body_start + content_length:]
                    try:
                        msg = json.loads(body.decode("utf-8"))
                        self._lsp_handle_message(msg)
                    except json.JSONDecodeError:
                        pass
            except Exception:
                break
        with self.lsp_lock:
            self.lsp_enabled = False

    def _lsp_handle_message(self, msg):
        """Handle an incoming LSP message."""
        with self.lsp_lock:
            if "id" in msg and "method" not in msg:
                # Response to our request
                rid = msg["id"]
                self.lsp_responses[rid] = msg
                # Prune old responses to prevent memory leak
                if len(self.lsp_responses) > 50:
                    oldest_keys = sorted(self.lsp_responses.keys())[:25]
                    for k in oldest_keys:
                        self.lsp_responses.pop(k, None)
                result = msg.get("result", {})
                # Handle initialize response
                if result and "capabilities" in result:
                    self.lsp_capabilities = result["capabilities"]
                    self.lsp_initialized = True
                    self._lsp_send_notification("initialized", {})
                    self._lsp_did_open()
                    self.message = f"LSP: {self.lsp_server_cmd[0]} ready"
            elif "method" in msg:
                method = msg["method"]
                params = msg.get("params", {})
                if method == "textDocument/publishDiagnostics":
                    self._lsp_handle_diagnostics(params)
                elif method == "window/logMessage":
                    pass  # Ignore log messages

    def _lsp_handle_diagnostics(self, params):
        """Process diagnostics from the LSP server."""
        diags = []
        for d in params.get("diagnostics", []):
            rng = d.get("range", {})
            start = rng.get("start", {})
            line = start.get("line", 0)
            col = start.get("character", 0)
            severity = d.get("severity", 1)  # 1=error, 2=warning, 3=info, 4=hint
            message = d.get("message", "")
            diags.append((line, col, severity, message))
        self.lsp_diagnostics = diags

    def _lsp_did_open(self):
        """Notify LSP that a document was opened."""
        if not self.filepath or not self.lsp_initialized:
            return
        lang_id = self.syntax_language or "plaintext"
        text = "\n".join(self.lines)
        self._lsp_send_notification("textDocument/didOpen", {
            "textDocument": {
                "uri": f"file://{os.path.abspath(self.filepath)}",
                "languageId": lang_id,
                "version": 1,
                "text": text,
            }
        })

    def lsp_did_change(self):
        """Notify LSP that the document changed (full sync)."""
        if not self.lsp_enabled or not self.lsp_initialized or not self.filepath:
            return
        text = "\n".join(self.lines)
        self._lsp_send_notification("textDocument/didChange", {
            "textDocument": {
                "uri": f"file://{os.path.abspath(self.filepath)}",
                "version": self.lsp_request_id,
            },
            "contentChanges": [{"text": text}],
        })

    def lsp_goto_definition(self):
        """Request go-to-definition from LSP."""
        if not self.lsp_enabled or not self.lsp_initialized or not self.filepath:
            self.message = "LSP not active"
            return
        rid = self._lsp_send_request("textDocument/definition", {
            "textDocument": {"uri": f"file://{os.path.abspath(self.filepath)}"},
            "position": {"line": self.cy, "character": self.cx},
        })
        # Wait briefly for response
        for _ in range(50):
            with self.lsp_lock:
                if rid in self.lsp_responses:
                    resp = self.lsp_responses.pop(rid)
                    result = resp.get("result")
                    if result:
                        loc = result if isinstance(result, dict) else result[0] if isinstance(result, list) and result else None
                        if loc:
                            uri = loc.get("uri", "")
                            rng = loc.get("range", {}).get("start", {})
                            target_line = rng.get("line", 0)
                            target_col = rng.get("character", 0)
                            fpath = uri.replace("file://", "")
                            if fpath != os.path.abspath(self.filepath):
                                self.jumplist_push()
                                self.open_file(fpath)
                            else:
                                self.jumplist_push()
                            self.cy = target_line
                            self.cx = target_col
                            self.message = f"Definition: line {target_line + 1}"
                            return
                    self.message = "No definition found"
                    return
            time.sleep(0.02)
        self.message = "LSP: definition request timed out"

    def lsp_hover(self):
        """Request hover info from LSP."""
        if not self.lsp_enabled or not self.lsp_initialized or not self.filepath:
            self.message = "LSP not active"
            return
        rid = self._lsp_send_request("textDocument/hover", {
            "textDocument": {"uri": f"file://{os.path.abspath(self.filepath)}"},
            "position": {"line": self.cy, "character": self.cx},
        })
        for _ in range(50):
            with self.lsp_lock:
                if rid in self.lsp_responses:
                    resp = self.lsp_responses.pop(rid)
                    result = resp.get("result")
                    if result:
                        contents = result.get("contents", "")
                        if isinstance(contents, dict):
                            text = contents.get("value", str(contents))
                        elif isinstance(contents, list):
                            text = " | ".join(c.get("value", str(c)) if isinstance(c, dict) else str(c) for c in contents)
                        else:
                            text = str(contents)
                        # Strip markdown fences
                        text = re.sub(r'```\w*\n?', '', text).strip()
                        self.lsp_hover_text = text
                        self.message = text[:200]
                    else:
                        self.message = "No hover info"
                    return
            time.sleep(0.02)
        self.message = "LSP: hover request timed out"

    def lsp_completion(self):
        """Request completions from LSP."""
        if not self.lsp_enabled or not self.lsp_initialized or not self.filepath:
            return
        rid = self._lsp_send_request("textDocument/completion", {
            "textDocument": {"uri": f"file://{os.path.abspath(self.filepath)}"},
            "position": {"line": self.cy, "character": self.cx},
        })
        for _ in range(50):
            with self.lsp_lock:
                if rid in self.lsp_responses:
                    resp = self.lsp_responses.pop(rid)
                    result = resp.get("result")
                    items = []
                    if isinstance(result, dict):
                        items = result.get("items", [])
                    elif isinstance(result, list):
                        items = result
                    self.lsp_completions = [(it.get("label", ""), it.get("detail", "")) for it in items[:50]]
                    if self.lsp_completions:
                        self.lsp_completion_active = True
                        self.lsp_completion_idx = 0
                    else:
                        self.message = "No completions"
                    return
            time.sleep(0.02)
        self.message = "LSP: completion request timed out"

    def lsp_apply_completion(self):
        """Apply the selected LSP completion."""
        if not self.lsp_completions or not self.lsp_completion_active:
            return
        label, _ = self.lsp_completions[self.lsp_completion_idx]
        # Find the word prefix to replace
        line = self.lines[self.cy]
        start = self.cx
        while start > 0 and (line[start - 1].isalnum() or line[start - 1] == '_'):
            start -= 1
        self.snapshot()
        self.lines[self.cy] = line[:start] + label + line[self.cx:]
        self.cx = start + len(label)
        self.lsp_completion_active = False
        self.lsp_completions = []
        self.dirty = True
        self.lsp_did_change()

    def lsp_references(self):
        """Request references from LSP."""
        if not self.lsp_enabled or not self.lsp_initialized or not self.filepath:
            self.message = "LSP not active"
            return
        rid = self._lsp_send_request("textDocument/references", {
            "textDocument": {"uri": f"file://{os.path.abspath(self.filepath)}"},
            "position": {"line": self.cy, "character": self.cx},
            "context": {"includeDeclaration": True},
        })
        for _ in range(50):
            with self.lsp_lock:
                if rid in self.lsp_responses:
                    resp = self.lsp_responses.pop(rid)
                    result = resp.get("result", [])
                    if result:
                        refs = []
                        for r in result[:20]:
                            uri = r.get("uri", "").replace("file://", "")
                            ln = r.get("range", {}).get("start", {}).get("line", 0)
                            fname = os.path.basename(uri)
                            refs.append(f"{fname}:{ln + 1}")
                        self.message = f"Refs({len(result)}): " + ", ".join(refs[:5])
                    else:
                        self.message = "No references found"
                    return
            time.sleep(0.02)
        self.message = "LSP: references request timed out"

    # ── Tab/Buffer Bar ─────────────────────────────────────────────

    def _draw_tabline(self, stdscr, editor_left, editor_w, width):
        """Draw a tab/buffer bar at the top of the editor."""
        tab_attr_active = getattr(self, 'color_tab_active', curses.A_REVERSE | curses.A_BOLD)
        tab_attr_inactive = getattr(self, 'color_tab_inactive', curses.A_DIM)
        bg = getattr(self, 'color_bg', curses.A_NORMAL)
        x = editor_left
        max_x = width - 1
        # Fill the tab bar row with background
        try:
            stdscr.addstr(0, editor_left, " " * min(editor_w, max_x - editor_left), bg)
        except curses.error:
            pass
        for i, buf_path in enumerate(self.buffer_order):
            if x >= max_x:
                break
            name = os.path.basename(buf_path) if buf_path != "[No Name]" else "[No Name]"
            is_active = (i == self.current_buffer_idx)
            # Show modified marker
            if buf_path == self.filepath and self.dirty:
                name += "●"
            label = f" {name} "
            attr = tab_attr_active if is_active else tab_attr_inactive
            tab_len = len(label)
            if x + tab_len > max_x:
                label = label[:max_x - x]
            try:
                stdscr.addstr(0, x, label, attr)
            except curses.error:
                pass
            x += tab_len
            # Separator
            if x < max_x:
                try:
                    stdscr.addstr(0, x, "│", curses.A_DIM | bg)
                except curses.error:
                    pass
                x += 1

    # ── Bracket Match Finding ──────────────────────────────────────

    def _find_bracket_match(self):
        """Find the matching bracket for the character under cursor."""
        if self.cy >= len(self.lines):
            return
        line = self.lines[self.cy]
        if self.cx >= len(line):
            return
        ch = line[self.cx]
        pairs = {'(': ')', ')': '(', '[': ']', ']': '[', '{': '}', '}': '{'}
        if ch not in pairs:
            return
        target = pairs[ch]
        forward = ch in ('(', '[', '{')
        depth = 0
        if forward:
            for row in range(self.cy, min(self.cy + 200, len(self.lines))):
                start = self.cx + 1 if row == self.cy else 0
                for col in range(start, len(self.lines[row])):
                    c = self.lines[row][col]
                    if c == ch:
                        depth += 1
                    elif c == target:
                        if depth == 0:
                            self._bracket_match_pos = (row, col)
                            return
                        depth -= 1
        else:
            for row in range(self.cy, max(self.cy - 200, -1), -1):
                end = self.cx - 1 if row == self.cy else len(self.lines[row]) - 1
                for col in range(end, -1, -1):
                    c = self.lines[row][col]
                    if c == ch:
                        depth += 1
                    elif c == target:
                        if depth == 0:
                            self._bracket_match_pos = (row, col)
                            return
                        depth -= 1

    # ── Word Under Cursor Highlighting ─────────────────────────────

    def _find_word_highlights(self):
        """Find all occurrences of the word under cursor."""
        self._word_hl_positions = []
        if self.cy >= len(self.lines):
            return
        line = self.lines[self.cy]
        if self.cx >= len(line):
            return
        ch = line[self.cx] if self.cx < len(line) else ''
        if not (ch.isalnum() or ch == '_'):
            return
        # Extract word under cursor
        start = self.cx
        while start > 0 and (line[start - 1].isalnum() or line[start - 1] == '_'):
            start -= 1
        end = self.cx
        while end < len(line) and (line[end].isalnum() or line[end] == '_'):
            end += 1
        word = line[start:end]
        if len(word) < 2:
            return
        # Find all occurrences in visible lines (limit to ~100 lines for perf)
        vis_start = max(0, self.cy - 50)
        vis_end = min(len(self.lines), self.cy + 50)
        for row in range(vis_start, vis_end):
            ln = self.lines[row]
            idx = 0
            while True:
                pos = ln.find(word, idx)
                if pos < 0:
                    break
                # Check word boundary
                before_ok = (pos == 0 or not (ln[pos - 1].isalnum() or ln[pos - 1] == '_'))
                after_ok = (pos + len(word) >= len(ln) or not (ln[pos + len(word)].isalnum() or ln[pos + len(word)] == '_'))
                if before_ok and after_ok:
                    self._word_hl_positions.append((row, pos, pos + len(word)))
                idx = pos + 1

    # ── Move Line Up/Down ──────────────────────────────────────────

    def move_line_up(self):
        """Move the current line up one position (Alt+Up / Alt+k)."""
        if self.cy <= 0:
            return
        self.lines[self.cy], self.lines[self.cy - 1] = self.lines[self.cy - 1], self.lines[self.cy]
        self.cy -= 1
        self.mark_dirty()
        self.message = "Line moved up"

    def move_line_down(self):
        """Move the current line down one position (Alt+Down / Alt+j)."""
        if self.cy >= len(self.lines) - 1:
            return
        self.lines[self.cy], self.lines[self.cy + 1] = self.lines[self.cy + 1], self.lines[self.cy]
        self.cy += 1
        self.mark_dirty()
        self.message = "Line moved down"

    # ── Duplicate Line ─────────────────────────────────────────────

    def duplicate_line(self):
        """Duplicate the current line below (Alt+d)."""
        line = self.lines[self.cy]
        self.lines.insert(self.cy + 1, line)
        self.cy += 1
        self.mark_dirty()
        self.message = "Line duplicated"

    # ── Emacs-Style Settings Menu ──────────────────────────────────

    def _get_menu_items(self):
        """Build the list of menu items for the settings panel."""
        themes = [
            "classic_blue", "neon_nights", "desert_storm", "sunny_meadow",
            "vampire_castle", "arctic_aurora", "forest_grove", "golden_wheat",
            "midnight_sky", "cloudy_day", "city_lights", "creamy_latte",
            "deep_space", "fresh_breeze", "matrix_code", "ocean_blue",
            "fire_red", "forest_green", "purple_haze", "sunset_orange",
            "arctic_white", "midnight_purple", "desert_gold", "cyber_pink",
        ]
        current_theme = self.options.get("theme", "classic_blue")
        theme_idx = themes.index(current_theme) if current_theme in themes else 0
        items = [
            ("header", "Display", None),
            ("bool", "Line Numbers", "number"),
            ("bool", "Relative Numbers", "relativenumber"),
            ("bool", "Indent Guides", "indent_guides"),
            ("bool", "Cursor Line Highlight", "cursorline"),
            ("bool", "Word Wrap", "wrap"),
            ("bool", "Status Line", "statusline"),
            ("bool", "Tab/Buffer Bar", "tabline"),
            ("bool", "Show Command", "show_command"),
            ("header", "Editor", None),
            ("bool", "Mouse Support", "mouse"),
            ("bool", "Error Lens (inline diag)", "error_lens"),
            ("bool", "Bracket Highlight", "bracket_highlight"),
            ("bool", "Word Highlight", "word_highlight"),
            ("bool", "Auto Save", "autosave"),
            ("int", "Tab Size", "tabsize"),
            ("int", "Auto Save Delay (s)", "autosave_delay"),
            ("header", "Panels", None),
            ("bool", "File Explorer", "explorer"),
            ("bool", "Minimap", "minimap"),
            ("header", "Appearance", None),
            ("theme", "Theme", (themes, theme_idx)),
            ("header", "", None),
            ("action", "[S] Save Config to evimrc.py", "save"),
            ("action", "[R] Reload Config", "reload"),
            ("header", "", None),
            ("info", f"Terminal Colors: {self._color_depth}", None),
            ("info", f"Language: {self.syntax_language or 'none'}", None),
            ("info", f"File: {self.filepath or '[No Name]'}", None),
        ]
        return items

    def draw_menu(self, stdscr, height, width):
        """Draw the Emacs-style settings menu overlay."""
        bg = getattr(self, 'color_bg', curses.A_NORMAL)
        hl = getattr(self, 'color_menu_hl', curses.A_REVERSE)
        hdr_attr = getattr(self, 'color_menu_header', curses.A_BOLD | curses.A_REVERSE)
        items = self._get_menu_items()
        # Box dimensions
        box_w = min(50, width - 4)
        box_h = min(len(items) + 4, height - 2)
        box_x = max(0, (width - box_w) // 2)
        box_y = max(0, (height - box_h) // 2)
        # Draw box background
        for row in range(box_h):
            y = box_y + row
            if y >= height:
                break
            try:
                stdscr.addstr(y, box_x, " " * box_w, bg)
            except curses.error:
                pass
        # Title bar
        title = " EVim Settings (F10 / Alt+x) "
        title_line = "╔" + title.center(box_w - 2, "═") + "╗"
        try:
            stdscr.addstr(box_y, box_x, title_line[:box_w], hdr_attr)
        except curses.error:
            pass
        # Items
        visible_items = box_h - 3  # title + bottom border + hint
        scroll = max(0, self.menu_cursor - visible_items + 2)
        for i in range(visible_items):
            item_idx = scroll + i
            y = box_y + 1 + i
            if y >= box_y + box_h - 2:
                break
            if item_idx >= len(items):
                try:
                    stdscr.addstr(y, box_x, "║" + " " * (box_w - 2) + "║", bg)
                except curses.error:
                    pass
                continue
            kind, label, data = items[item_idx]
            is_selected = (item_idx == self.menu_cursor)
            attr = hl if is_selected else bg
            if kind == "header":
                line_text = f"║ ── {label} ──".ljust(box_w - 1) + "║"
                try:
                    stdscr.addstr(y, box_x, line_text[:box_w], hdr_attr if label else bg)
                except curses.error:
                    pass
                continue
            elif kind == "bool":
                val = self.options.get(data, False)
                checkbox = "[x]" if val else "[ ]"
                line_text = f"║  {checkbox} {label}".ljust(box_w - 1) + "║"
            elif kind == "int":
                val = self.options.get(data, 0)
                line_text = f"║    {label}: {val}  (←/→ to change)".ljust(box_w - 1) + "║"
            elif kind == "theme":
                themes, tidx = data
                current = themes[tidx % len(themes)]
                display = current.replace("_", " ").title()
                line_text = f"║  ◀ {display} ▶  (←/→ to change)".ljust(box_w - 1) + "║"
            elif kind == "action":
                line_text = f"║  {label}".ljust(box_w - 1) + "║"
            elif kind == "info":
                line_text = f"║    {label}".ljust(box_w - 1) + "║"
            else:
                line_text = f"║  {label}".ljust(box_w - 1) + "║"
            try:
                stdscr.addstr(y, box_x, line_text[:box_w], attr)
            except curses.error:
                pass
        # Bottom border + hint
        hint = " Enter:Toggle  ←→:Adjust  S:Save  Esc:Close "
        bottom = "╚" + hint.center(box_w - 2, "═") + "╝"
        try:
            stdscr.addstr(box_y + box_h - 1, box_x, bottom[:box_w], hdr_attr)
        except curses.error:
            pass

    def handle_menu_key(self, stdscr):
        """Handle key input in the settings menu."""
        ch = stdscr.getch()
        if ch < 0:
            return
        items = self._get_menu_items()
        # Close menu
        if ch in (27, curses.KEY_F5, ord('q'), ord('Q')):
            self.menu_visible = False
            self.message = "Menu closed"
            return
        # Navigate
        if ch == curses.KEY_UP or ch == ord('k'):
            self.menu_cursor = max(0, self.menu_cursor - 1)
            # Skip headers
            while self.menu_cursor > 0 and items[self.menu_cursor][0] in ("header", "info"):
                self.menu_cursor -= 1
            if items[self.menu_cursor][0] in ("header", "info"):
                self.menu_cursor += 1
                while self.menu_cursor < len(items) and items[self.menu_cursor][0] in ("header", "info"):
                    self.menu_cursor += 1
            return
        if ch == curses.KEY_DOWN or ch == ord('j'):
            self.menu_cursor = min(len(items) - 1, self.menu_cursor + 1)
            # Skip headers
            while self.menu_cursor < len(items) - 1 and items[self.menu_cursor][0] in ("header", "info"):
                self.menu_cursor += 1
            return
        # Save shortcut
        if ch == ord('s') or ch == ord('S'):
            self.save_config()
            self.menu_visible = False
            return
        # Reload config shortcut
        if ch == ord('r') or ch == ord('R'):
            self.load_config()
            self.menu_visible = False
            return
        if self.menu_cursor >= len(items):
            return
        kind, label, data = items[self.menu_cursor]
        # Toggle bool
        if kind == "bool" and ch in (curses.KEY_ENTER, 10, 13, ord(' ')):
            self.options[data] = not self.options.get(data, False)
            # Apply side effects
            if data == "explorer":
                if self.options[data]:
                    self.explorer_toggle()
                else:
                    self.explorer_visible = False
            elif data == "minimap":
                self.minimap_visible = self.options[data]
            self.message = f"{label}: {'ON' if self.options[data] else 'OFF'}"
            return
        # Adjust int
        if kind == "int":
            if ch == curses.KEY_RIGHT or ch == ord('l'):
                self.options[data] = self.options.get(data, 0) + 1
                self.message = f"{label}: {self.options[data]}"
                return
            if ch == curses.KEY_LEFT or ch == ord('h'):
                self.options[data] = max(1, self.options.get(data, 0) - 1)
                self.message = f"{label}: {self.options[data]}"
                return
        # Adjust theme
        if kind == "theme":
            themes, tidx = data
            if ch == curses.KEY_RIGHT or ch == ord('l') or ch in (curses.KEY_ENTER, 10, 13, ord(' ')):
                tidx = (tidx + 1) % len(themes)
                self.set_theme(themes[tidx])
                return
            if ch == curses.KEY_LEFT or ch == ord('h'):
                tidx = (tidx - 1) % len(themes)
                self.set_theme(themes[tidx])
                return
        # Action items
        if kind == "action" and ch in (curses.KEY_ENTER, 10, 13, ord(' ')):
            if data == "save":
                self.save_config()
                self.menu_visible = False
            elif data == "reload":
                self.load_config()
                self.menu_visible = False
            return

    # ── Save Config ────────────────────────────────────────────────

    def save_config(self):
        """Save current settings to evimrc.py in the current directory."""
        config_path = Path.cwd() / "evimrc.py"
        lines = [
            "# evim config file — this is Python!",
            "# Auto-saved by EVim settings menu (F10)",
            "# The 'editor' object is injected automatically — do not reassign it.",
            "",
            "# Theme",
            f"editor.set_theme('{self.options.get('theme', 'classic_blue')}')",
            "",
            "# Display options",
        ]
        bool_opts = [
            ('number', 'Line Numbers'),
            ('relativenumber', 'Relative Numbers'),
            ('indent_guides', 'Indent Guides'),
            ('cursorline', 'Cursor Line'),
            ('wrap', 'Word Wrap'),
            ('statusline', 'Status Line'),
            ('tabline', 'Tab Bar'),
            ('show_command', 'Show Command'),
        ]
        for opt, comment in bool_opts:
            lines.append(f"editor.options['{opt}'] = {self.options.get(opt, False)}")
        lines.append("")
        lines.append("# Editor options")
        editor_opts = [
            ('mouse', 'Mouse'),
            ('error_lens', 'Error Lens'),
            ('bracket_highlight', 'Bracket Highlight'),
            ('word_highlight', 'Word Highlight'),
            ('autosave', 'Auto Save'),
        ]
        for opt, comment in editor_opts:
            lines.append(f"editor.options['{opt}'] = {self.options.get(opt, False)}")
        lines.append(f"editor.options['tabsize'] = {self.options.get('tabsize', 4)}")
        lines.append(f"editor.options['autosave_delay'] = {self.options.get('autosave_delay', 5)}")
        lines.append("")
        lines.append("# Panel options")
        lines.append(f"editor.options['explorer'] = {self.options.get('explorer', False)}")
        lines.append(f"editor.options['minimal'] = {self.options.get('minimal', False)}")
        lines.append("")
        lines.append("editor.message = 'Config Loaded'")
        try:
            config_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
            self.message = f"Config saved to {config_path.name}"
        except Exception as exc:
            self.message = f"Save config failed: {exc}"

    # ── Recent Files ───────────────────────────────────────────────

    def _load_recent_files(self):
        """Load recent files list from disk."""
        try:
            if self._recent_file_path.exists():
                self.recent_files = json.loads(self._recent_file_path.read_text())[:self.recent_files_max]
        except Exception:
            self.recent_files = []

    def _save_recent_files(self):
        """Persist recent files list."""
        try:
            self._recent_file_path.parent.mkdir(parents=True, exist_ok=True)
            self._recent_file_path.write_text(json.dumps(self.recent_files[:self.recent_files_max]))
        except Exception:
            pass

    def _add_recent_file(self, filepath):
        """Add a file to the recent files list."""
        abspath = str(Path(filepath).resolve())
        if abspath in self.recent_files:
            self.recent_files.remove(abspath)
        self.recent_files.insert(0, abspath)
        self.recent_files = self.recent_files[:self.recent_files_max]
        self._save_recent_files()

    # ── Kill Ring ──────────────────────────────────────────────────

    def kill_ring_push(self, text):
        """Push text onto the kill ring."""
        if not text:
            return
        self.kill_ring.insert(0, text)
        if len(self.kill_ring) > self.kill_ring_max:
            self.kill_ring.pop()
        self.kill_ring_idx = 0

    def kill_ring_yank(self):
        """Paste from kill ring at current position."""
        if not self.kill_ring:
            self.message = "Kill ring empty"
            return
        text = self.kill_ring[self.kill_ring_idx]
        self.snapshot()
        for ch in text:
            if ch == '\n':
                self.newline()
            else:
                self.insert_char(ch)
        self.mark_dirty()
        self.message = f"Yanked from kill ring [{self.kill_ring_idx + 1}/{len(self.kill_ring)}]"

    def kill_ring_rotate(self):
        """Rotate through kill ring (like Emacs M-y)."""
        if len(self.kill_ring) < 2:
            self.message = "Kill ring has only one entry"
            return
        self.kill_ring_idx = (self.kill_ring_idx + 1) % len(self.kill_ring)
        self.message = f"Kill ring [{self.kill_ring_idx + 1}/{len(self.kill_ring)}]: {self.kill_ring[self.kill_ring_idx][:40]}"

    # ── Incremental Search ─────────────────────────────────────────

    def isearch_start(self):
        """Start incremental search (Ctrl+f / C-s Emacs style)."""
        self._isearch_active = True
        self._isearch_matches = []
        self._isearch_idx = 0
        self._isearch_origin = (self.cy, self.cx)
        self.mode = "command"
        self.command = "/"
        self.message = "I-Search: "

    def isearch_update(self, pattern):
        """Update incremental search matches as user types."""
        self._isearch_matches = []
        if not pattern:
            return
        try:
            regex = re.compile(re.escape(pattern), re.IGNORECASE)
        except re.error:
            return
        for i, line in enumerate(self.lines):
            for m in regex.finditer(line):
                self._isearch_matches.append((i, m.start(), m.end() - m.start()))
        # Jump to first match at or after origin
        if self._isearch_matches:
            oy, ox = self._isearch_origin
            for idx, (line, col, _) in enumerate(self._isearch_matches):
                if line > oy or (line == oy and col >= ox):
                    self._isearch_idx = idx
                    self.cy = line
                    self.cx = col
                    return
            # Wrap around
            self._isearch_idx = 0
            self.cy = self._isearch_matches[0][0]
            self.cx = self._isearch_matches[0][1]

    def isearch_next(self):
        """Jump to next incremental search match."""
        if not self._isearch_matches:
            return
        self._isearch_idx = (self._isearch_idx + 1) % len(self._isearch_matches)
        line, col, _ = self._isearch_matches[self._isearch_idx]
        self.cy = line
        self.cx = col

    def isearch_prev(self):
        """Jump to previous incremental search match."""
        if not self._isearch_matches:
            return
        self._isearch_idx = (self._isearch_idx - 1) % len(self._isearch_matches)
        line, col, _ = self._isearch_matches[self._isearch_idx]
        self.cy = line
        self.cx = col

    # ── Code Folding ───────────────────────────────────────────────

    def fold_toggle(self):
        """Toggle fold at current line (za)."""
        if self.cy in self.folds:
            del self.folds[self.cy]
            self.message = "Fold opened"
        else:
            end = self._find_fold_end(self.cy)
            if end > self.cy:
                self.folds[self.cy] = end
                self.message = f"Folded lines {self.cy + 1}-{end + 1}"

    def fold_open(self):
        """Open fold at current line (zo)."""
        if self.cy in self.folds:
            del self.folds[self.cy]
            self.message = "Fold opened"
        else:
            # Check if we're inside a fold
            for start, end in list(self.folds.items()):
                if start < self.cy <= end:
                    del self.folds[start]
                    self.message = "Fold opened"
                    return

    def fold_close(self):
        """Close fold at current line (zc)."""
        end = self._find_fold_end(self.cy)
        if end > self.cy:
            self.folds[self.cy] = end
            self.message = f"Folded lines {self.cy + 1}-{end + 1}"

    def fold_all(self):
        """Fold all top-level blocks (zM)."""
        self.folds.clear()
        i = 0
        while i < len(self.lines):
            end = self._find_fold_end(i)
            if end > i:
                self.folds[i] = end
                i = end + 1
            else:
                i += 1
        self.message = f"Folded {len(self.folds)} regions"

    def unfold_all(self):
        """Open all folds (zR)."""
        count = len(self.folds)
        self.folds.clear()
        self.message = f"Opened {count} folds"

    def _find_fold_end(self, start_line):
        """Find the end of a foldable block starting at start_line."""
        if start_line >= len(self.lines):
            return start_line
        line = self.lines[start_line]
        stripped = line.lstrip()
        if not stripped:
            return start_line
        base_indent = len(line) - len(stripped)
        # Look for indented block following this line
        end = start_line
        for i in range(start_line + 1, len(self.lines)):
            ln = self.lines[i]
            if not ln.strip():  # blank lines are part of the fold
                end = i
                continue
            indent = len(ln) - len(ln.lstrip())
            if indent > base_indent:
                end = i
            else:
                break
        return end

    def _visible_line_index(self, display_row):
        """Convert a display row to actual line index, accounting for folds."""
        actual = 0
        display = 0
        while actual < len(self.lines) and display < display_row:
            if actual in self.folds:
                actual = self.folds[actual] + 1
            else:
                actual += 1
            display += 1
        return actual

    def _display_line_count(self):
        """Count visible lines (not hidden by folds)."""
        count = 0
        i = 0
        while i < len(self.lines):
            count += 1
            if i in self.folds:
                i = self.folds[i] + 1
            else:
                i += 1
        return count

    # ── Right-Click Context Menu ───────────────────────────────────

    def _show_context_menu(self, stdscr, mx, my):
        """Show a right-click context menu at the given position."""
        self._ctx_menu_items = [
            ("Cut", self._ctx_cut),
            ("Copy", self._ctx_copy),
            ("Paste", self._ctx_paste),
            ("─────────", None),
            ("Select All", self._ctx_select_all),
            ("─────────", None),
            ("Go to Definition", self._ctx_goto_def),
            ("Find References", self._ctx_find_refs),
            ("─────────", None),
            ("Fold/Unfold", lambda: self.fold_toggle()),
            ("Toggle Comment", lambda: self.toggle_comment()),
            ("─────────", None),
            ("Close Buffer", self._ctx_close_buffer),
        ]
        self._ctx_menu_visible = True
        self._ctx_menu_x = mx
        self._ctx_menu_y = my
        self._ctx_menu_cursor = 0

    def _draw_context_menu(self, stdscr, height, width):
        """Draw the right-click context menu."""
        if not self._ctx_menu_visible:
            return
        items = self._ctx_menu_items
        menu_w = max(len(label) for label, _ in items) + 4
        menu_h = len(items) + 2
        x = min(self._ctx_menu_x, width - menu_w - 1)
        y = min(self._ctx_menu_y, height - menu_h - 1)
        bg = getattr(self, 'color_bg', curses.A_NORMAL)
        hl = getattr(self, 'color_menu_hl', curses.A_REVERSE)
        # Border top
        try:
            stdscr.addstr(y, x, "┌" + "─" * (menu_w - 2) + "┐", bg | curses.A_BOLD)
        except curses.error:
            pass
        for i, (label, action) in enumerate(items):
            row = y + 1 + i
            is_sep = action is None
            is_sel = (i == self._ctx_menu_cursor and not is_sep)
            attr = hl if is_sel else bg
            if is_sep:
                line = "├" + "─" * (menu_w - 2) + "┤"
            else:
                line = "│ " + label.ljust(menu_w - 4) + " │"
            try:
                stdscr.addstr(row, x, line, attr)
            except curses.error:
                pass
        # Border bottom
        try:
            stdscr.addstr(y + menu_h - 1, x, "└" + "─" * (menu_w - 2) + "┘", bg | curses.A_BOLD)
        except curses.error:
            pass

    def _handle_context_menu_key(self, ch):
        """Handle keys while context menu is visible."""
        items = self._ctx_menu_items
        if ch == 27 or ch == ord('q'):  # ESC / q
            self._ctx_menu_visible = False
            return True
        if ch == curses.KEY_UP or ch == ord('k'):
            self._ctx_menu_cursor = max(0, self._ctx_menu_cursor - 1)
            while self._ctx_menu_cursor > 0 and items[self._ctx_menu_cursor][1] is None:
                self._ctx_menu_cursor -= 1
            if items[self._ctx_menu_cursor][1] is None:
                self._ctx_menu_cursor += 1
            return True
        if ch == curses.KEY_DOWN or ch == ord('j'):
            self._ctx_menu_cursor = min(len(items) - 1, self._ctx_menu_cursor + 1)
            while self._ctx_menu_cursor < len(items) - 1 and items[self._ctx_menu_cursor][1] is None:
                self._ctx_menu_cursor += 1
            return True
        if ch in (curses.KEY_ENTER, 10, 13, ord(' ')):
            label, action = items[self._ctx_menu_cursor]
            self._ctx_menu_visible = False
            if action:
                action()
            return True
        # Mouse click on menu item
        if ch == curses.KEY_MOUSE:
            try:
                _, mx, my, _, bstate = curses.getmouse()
                if bstate & (curses.BUTTON1_CLICKED | curses.BUTTON1_PRESSED):
                    idx = my - self._ctx_menu_y - 1
                    if 0 <= idx < len(items) and items[idx][1] is not None:
                        self._ctx_menu_visible = False
                        items[idx][1]()
                    else:
                        self._ctx_menu_visible = False
                    return True
            except curses.error:
                pass
            self._ctx_menu_visible = False
            return True
        return True  # consume all keys while menu is open

    def _ctx_cut(self):
        if self.selection:
            self.snapshot()
            self.yank_selection()
            text = self.clipboard
            self.kill_ring_push(text)
            self.delete_selection()
        else:
            self.snapshot()
            text = self.lines[self.cy]
            self.kill_ring_push(text)
            self.delete_line()

    def _ctx_copy(self):
        if self.selection:
            self.yank_selection()
            self.kill_ring_push(self.clipboard)
        else:
            self.yank_line()
            self.kill_ring_push(self.clipboard)

    def _ctx_paste(self):
        self.snapshot()
        if self.kill_ring:
            text = self.kill_ring[0]
            for ch in text:
                if ch == '\n':
                    self.newline()
                else:
                    self.insert_char(ch)
        elif self.clipboard:
            self.paste()

    def _ctx_select_all(self):
        self.selection = (0, 0)
        self.cy = len(self.lines) - 1
        self.cx = len(self.lines[self.cy])
        self.message = "All text selected"

    def _ctx_goto_def(self):
        if self.lsp_enabled and self.lsp_initialized:
            self.lsp_goto_definition()

    def _ctx_find_refs(self):
        if self.lsp_enabled and self.lsp_initialized:
            self.lsp_find_references()

    def _ctx_close_buffer(self):
        if len(self.buffer_order) <= 1:
            self.message = "Cannot close last buffer"
            return
        path = self.filepath
        idx = self.current_buffer_idx
        del self.buffers[path]
        self.buffer_order.remove(path)
        self.current_buffer_idx = min(idx, len(self.buffer_order) - 1)
        self.filepath = self.buffer_order[self.current_buffer_idx]
        self.lines = self.buffers[self.filepath][:]
        self.cy = min(self.cy, len(self.lines) - 1)
        self.cx = 0
        self.message = f"Closed buffer: {os.path.basename(path)}"

    # ── Command Palette ────────────────────────────────────────────

    def _build_palette_commands(self):
        """Build the full list of commands for the palette."""
        cmds = [
            ("Save File", lambda: self.quick_save()),
            ("Save As...", lambda: setattr(self, 'message', 'Use :w <filename>')),
            ("Open File (Fuzzy)", lambda: self.fuzzy_find()),
            ("Close Buffer", lambda: self._ctx_close_buffer()),
            ("Next Buffer", lambda: self.next_buffer()),
            ("Previous Buffer", lambda: self.prev_buffer()),
            ("Toggle File Explorer", lambda: self.explorer_toggle()),
            ("Toggle Terminal", lambda: self.term_toggle()),
            ("Toggle Minimap", lambda: self.minimap_toggle()),
            ("Toggle Line Numbers", lambda: self.options.__setitem__('number', not self.options.get('number'))),
            ("Toggle Relative Numbers", lambda: self.options.__setitem__('relativenumber', not self.options.get('relativenumber'))),
            ("Toggle Word Wrap", lambda: self.options.__setitem__('wrap', not self.options.get('wrap'))),
            ("Toggle Indent Guides", lambda: self.options.__setitem__('indent_guides', not self.options.get('indent_guides'))),
            ("Toggle Error Lens", lambda: self.options.__setitem__('error_lens', not self.options.get('error_lens'))),
            ("Toggle Bracket Highlight", lambda: self.options.__setitem__('bracket_highlight', not self.options.get('bracket_highlight'))),
            ("Toggle Word Highlight", lambda: self.options.__setitem__('word_highlight', not self.options.get('word_highlight'))),
            ("Toggle Auto Save", lambda: self.options.__setitem__('autosave', not self.options.get('autosave'))),
            ("Toggle Mouse", lambda: self.options.__setitem__('mouse', not self.options.get('mouse'))),
            ("Settings Menu", lambda: setattr(self, 'menu_visible', True)),
            ("Fold Toggle (za)", lambda: self.fold_toggle()),
            ("Fold All (zM)", lambda: self.fold_all()),
            ("Unfold All (zR)", lambda: self.unfold_all()),
            ("Go to Definition", lambda: self.lsp_goto_definition() if self.lsp_enabled else None),
            ("Find References", lambda: self.lsp_find_references() if self.lsp_enabled else None),
            ("Start LSP", lambda: self.lsp_start()),
            ("Stop LSP", lambda: self.lsp_stop()),
            ("Toggle Comment", lambda: self.toggle_comment()),
            ("Sort Lines", lambda: self._sort_lines()),
            ("Duplicate Line", lambda: (self.snapshot(), self.duplicate_line())),
            ("Move Line Up", lambda: (self.snapshot(), self.move_line_up())),
            ("Move Line Down", lambda: (self.snapshot(), self.move_line_down())),
            ("Select All", lambda: self._ctx_select_all()),
            ("Kill Ring Paste", lambda: self.kill_ring_yank()),
            ("Kill Ring Rotate", lambda: self.kill_ring_rotate()),
            ("Save Config", lambda: self.save_config()),
            ("Recent Files", lambda: self._show_recent_files()),
            ("Symbol Outline", lambda: self._build_outline()),
            ("Project Grep", lambda: setattr(self, 'message', 'Use :grep <pattern>')),
            ("Help", lambda: setattr(self, 'mode', 'overlay')),
            ("Quit", lambda: setattr(self, 'should_exit', True)),
        ]
        return cmds

    def palette_open(self):
        """Open the command palette (Ctrl+Shift+P / M-x style)."""
        self._palette_visible = True
        self._palette_query = ""
        self._palette_items = self._build_palette_commands()
        self._palette_filtered = self._palette_items[:]
        self._palette_cursor = 0

    def _palette_filter(self):
        """Filter palette items by fuzzy query."""
        if not self._palette_query:
            self._palette_filtered = self._palette_items[:]
        else:
            q = self._palette_query.lower()
            scored = []
            for label, action in self._palette_items:
                ll = label.lower()
                if q in ll:
                    # Prefer prefix matches
                    score = 0 if ll.startswith(q) else 1
                    scored.append((score, label, action))
                else:
                    # Fuzzy: all chars must appear in order
                    qi = 0
                    for c in ll:
                        if qi < len(q) and c == q[qi]:
                            qi += 1
                    if qi == len(q):
                        scored.append((2, label, action))
            scored.sort(key=lambda x: x[0])
            self._palette_filtered = [(label, action) for _, label, action in scored]
        self._palette_cursor = min(self._palette_cursor, max(0, len(self._palette_filtered) - 1))

    def draw_palette(self, stdscr, height, width):
        """Draw the command palette overlay."""
        if not self._palette_visible:
            return
        bg = getattr(self, 'color_bg', curses.A_NORMAL)
        hl = getattr(self, 'color_menu_hl', curses.A_REVERSE)
        hdr_attr = getattr(self, 'color_menu_header', curses.A_BOLD | curses.A_REVERSE)
        box_w = min(60, width - 4)
        box_h = min(20, height - 4)
        box_x = max(0, (width - box_w) // 2)
        box_y = max(1, height // 6)
        # Input line
        prompt = f" > {self._palette_query}█"
        try:
            stdscr.addstr(box_y, box_x, "╔" + "═" * (box_w - 2) + "╗", hdr_attr)
            stdscr.addstr(box_y + 1, box_x, ("║" + prompt.ljust(box_w - 2)[:box_w - 2] + "║"), hdr_attr)
            stdscr.addstr(box_y + 2, box_x, "╠" + "═" * (box_w - 2) + "╣", hdr_attr)
        except curses.error:
            pass
        # Items
        visible = box_h - 5
        scroll = max(0, self._palette_cursor - visible + 1)
        for i in range(visible):
            idx = scroll + i
            row = box_y + 3 + i
            if row >= box_y + box_h - 1:
                break
            if idx < len(self._palette_filtered):
                label, _ = self._palette_filtered[idx]
                attr = hl if idx == self._palette_cursor else bg
                text = ("║ " + label).ljust(box_w - 1)[:box_w - 1] + "║"
            else:
                text = "║" + " " * (box_w - 2) + "║"
                attr = bg
            try:
                stdscr.addstr(row, box_x, text, attr)
            except curses.error:
                pass
        # Bottom
        count_text = f" {len(self._palette_filtered)} commands "
        bottom = "╚" + count_text.center(box_w - 2, "═") + "╝"
        try:
            stdscr.addstr(box_y + box_h - 1, box_x, bottom[:box_w], hdr_attr)
        except curses.error:
            pass

    def handle_palette_key(self, stdscr):
        """Handle input in the command palette."""
        ch = stdscr.getch()
        if ch < 0:
            return
        if ch == 27:  # ESC
            self._palette_visible = False
            return
        if ch in (curses.KEY_ENTER, 10, 13):
            if self._palette_filtered:
                _, action = self._palette_filtered[self._palette_cursor]
                self._palette_visible = False
                if action:
                    action()
            else:
                self._palette_visible = False
            return
        if ch == curses.KEY_UP:
            self._palette_cursor = max(0, self._palette_cursor - 1)
            return
        if ch == curses.KEY_DOWN:
            self._palette_cursor = min(len(self._palette_filtered) - 1, self._palette_cursor + 1)
            return
        if ch in (curses.KEY_BACKSPACE, 127, curses.ascii.DEL):
            self._palette_query = self._palette_query[:-1]
            self._palette_filter()
            return
        if 0 <= ch < 256 and curses.ascii.isprint(ch):
            self._palette_query += chr(ch)
            self._palette_filter()
            return

    # ── Project Grep ───────────────────────────────────────────────

    def project_grep(self, pattern, path="."):
        """Search across project files using grep/ripgrep."""
        self._grep_results = []
        self._grep_cursor = 0
        try:
            # Prefer ripgrep, fall back to grep
            for cmd in (['rg', '--no-heading', '-n', pattern, path],
                        ['grep', '-rn', pattern, path]):
                try:
                    result = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
                    break
                except FileNotFoundError:
                    continue
            else:
                self.message = "Neither rg nor grep found"
                return
            for line in result.stdout.splitlines()[:500]:
                parts = line.split(":", 2)
                if len(parts) >= 3:
                    self._grep_results.append((parts[0], int(parts[1]), parts[2]))
            if self._grep_results:
                self._grep_visible = True
                self.message = f"Grep: {len(self._grep_results)} matches for '{pattern}'"
            else:
                self.message = f"Grep: no matches for '{pattern}'"
        except Exception as e:
            self.message = f"Grep error: {e}"

    def draw_grep_results(self, stdscr, height, width):
        """Draw grep results overlay."""
        if not self._grep_visible or not self._grep_results:
            return
        bg = getattr(self, 'color_bg', curses.A_NORMAL)
        hl = getattr(self, 'color_menu_hl', curses.A_REVERSE)
        hdr = getattr(self, 'color_menu_header', curses.A_BOLD | curses.A_REVERSE)
        box_w = min(80, width - 4)
        box_h = min(25, height - 4)
        box_x = max(0, (width - box_w) // 2)
        box_y = max(0, (height - box_h) // 2)
        title = f" Grep Results ({len(self._grep_results)} matches) "
        try:
            stdscr.addstr(box_y, box_x, ("╔" + title.center(box_w - 2, "═") + "╗")[:box_w], hdr)
        except curses.error:
            pass
        visible = box_h - 3
        scroll = max(0, self._grep_cursor - visible + 2)
        for i in range(visible):
            idx = scroll + i
            row = box_y + 1 + i
            if idx < len(self._grep_results):
                fpath, lineno, text = self._grep_results[idx]
                entry = f"  {fpath}:{lineno}: {text}"
                attr = hl if idx == self._grep_cursor else bg
            else:
                entry = ""
                attr = bg
            line = ("║" + entry).ljust(box_w - 1)[:box_w - 1] + "║"
            try:
                stdscr.addstr(row, box_x, line, attr)
            except curses.error:
                pass
        hint = " Enter:Open  j/k:Navigate  Esc:Close "
        try:
            stdscr.addstr(box_y + box_h - 1, box_x, ("╚" + hint.center(box_w - 2, "═") + "╝")[:box_w], hdr)
        except curses.error:
            pass

    def handle_grep_key(self, stdscr):
        """Handle keys in grep results view."""
        ch = stdscr.getch()
        if ch < 0:
            return
        if ch == 27 or ch == ord('q'):
            self._grep_visible = False
            return
        if ch == curses.KEY_UP or ch == ord('k'):
            self._grep_cursor = max(0, self._grep_cursor - 1)
            return
        if ch == curses.KEY_DOWN or ch == ord('j'):
            self._grep_cursor = min(len(self._grep_results) - 1, self._grep_cursor + 1)
            return
        if ch in (curses.KEY_ENTER, 10, 13):
            if self._grep_results:
                fpath, lineno, _ = self._grep_results[self._grep_cursor]
                self._grep_visible = False
                abspath = str(Path(fpath).resolve())
                if abspath != os.path.abspath(self.filepath or ""):
                    self.open_buffer(abspath)
                self.cy = max(0, lineno - 1)
                self.cx = 0
            return

    # ── Symbol Outline ─────────────────────────────────────────────

    def _build_outline(self):
        """Build a symbol outline from current file."""
        self._outline_items = []
        lang = self.syntax_language or ""
        patterns = []
        if lang in ("python",):
            patterns = [
                (r'^\s*(class\s+\w+)', 'class'),
                (r'^\s*(def\s+\w+)', 'function'),
                (r'^(\w+)\s*=', 'variable'),
            ]
        elif lang in ("javascript", "typescript", "jsx", "tsx"):
            patterns = [
                (r'^\s*(class\s+\w+)', 'class'),
                (r'^\s*(?:export\s+)?(?:async\s+)?function\s+(\w+)', 'function'),
                (r'^\s*(?:const|let|var)\s+(\w+)\s*=\s*(?:async\s+)?\(', 'function'),
                (r'^\s*(\w+)\s*\(', 'method'),
            ]
        elif lang in ("c", "cpp", "rust", "go", "java"):
            patterns = [
                (r'^\s*(?:pub\s+)?(?:fn|func|void|int|char|auto|static)\s+(\w+)\s*\(', 'function'),
                (r'^\s*(?:struct|class|enum|type)\s+(\w+)', 'class'),
            ]
        else:
            # Generic: look for function-like patterns
            patterns = [
                (r'^\s*(?:def|fn|func|function|sub|proc)\s+(\w+)', 'function'),
                (r'^\s*(?:class|struct|enum|type|interface)\s+(\w+)', 'class'),
            ]
        for i, line in enumerate(self.lines):
            for pat, kind in patterns:
                m = re.match(pat, line)
                if m:
                    name = m.group(1)
                    self._outline_items.append((name, kind, i))
                    break
        if self._outline_items:
            self._outline_visible = True
            self._outline_cursor = 0
            self.message = f"Outline: {len(self._outline_items)} symbols"
        else:
            self.message = "No symbols found"

    def draw_outline(self, stdscr, height, width):
        """Draw symbol outline overlay."""
        if not self._outline_visible:
            return
        bg = getattr(self, 'color_bg', curses.A_NORMAL)
        hl = getattr(self, 'color_menu_hl', curses.A_REVERSE)
        hdr = getattr(self, 'color_menu_header', curses.A_BOLD | curses.A_REVERSE)
        box_w = min(50, width - 4)
        box_h = min(len(self._outline_items) + 4, height - 2)
        box_x = max(0, (width - box_w) // 2)
        box_y = max(0, (height - box_h) // 2)
        title = f" Symbol Outline ({len(self._outline_items)}) "
        try:
            stdscr.addstr(box_y, box_x, ("╔" + title.center(box_w - 2, "═") + "╗")[:box_w], hdr)
        except curses.error:
            pass
        visible = box_h - 3
        scroll = max(0, self._outline_cursor - visible + 2)
        icons = {'function': 'ƒ', 'class': '◆', 'method': '●', 'variable': '▸'}
        for i in range(visible):
            idx = scroll + i
            row = box_y + 1 + i
            if idx < len(self._outline_items):
                name, kind, lineno = self._outline_items[idx]
                icon = icons.get(kind, '·')
                entry = f"  {icon} {name}  :{lineno + 1}"
                attr = hl if idx == self._outline_cursor else bg
            else:
                entry = ""
                attr = bg
            line = ("║" + entry).ljust(box_w - 1)[:box_w - 1] + "║"
            try:
                stdscr.addstr(row, box_x, line, attr)
            except curses.error:
                pass
        try:
            stdscr.addstr(box_y + box_h - 1, box_x, ("╚" + "═" * (box_w - 2) + "╝")[:box_w], hdr)
        except curses.error:
            pass

    def handle_outline_key(self, stdscr):
        """Handle keys in outline view."""
        ch = stdscr.getch()
        if ch < 0:
            return
        if ch == 27 or ch == ord('q'):
            self._outline_visible = False
            return
        if ch == curses.KEY_UP or ch == ord('k'):
            self._outline_cursor = max(0, self._outline_cursor - 1)
            return
        if ch == curses.KEY_DOWN or ch == ord('j'):
            self._outline_cursor = min(len(self._outline_items) - 1, self._outline_cursor + 1)
            return
        if ch in (curses.KEY_ENTER, 10, 13):
            if self._outline_items:
                _, _, lineno = self._outline_items[self._outline_cursor]
                self._outline_visible = False
                self.jumplist_push()
                self.cy = lineno
                self.cx = 0
                self.message = f"Jumped to line {lineno + 1}"
            return

    # ── Recent Files Popup ─────────────────────────────────────────

    def _show_recent_files(self):
        """Show recent files in a selection overlay."""
        if not self.recent_files:
            self.message = "No recent files"
            return
        # Reuse grep results UI
        self._grep_results = []
        for f in self.recent_files:
            name = os.path.basename(f)
            self._grep_results.append((f, 0, name))
        self._grep_visible = True
        self._grep_cursor = 0
        self.message = f"{len(self.recent_files)} recent files"

    # ── Surround Editing ───────────────────────────────────────────

    def surround_change(self, old_char, new_char):
        """Change surrounding pair (cs<old><new>)."""
        pairs = {
            '(': ('(', ')'), ')': ('(', ')'),
            '[': ('[', ']'), ']': ('[', ']'),
            '{': ('{', '}'), '}': ('{', '}'),
            '<': ('<', '>'), '>': ('<', '>'),
            '"': ('"', '"'), "'": ("'", "'"), '`': ('`', '`'),
        }
        if old_char not in pairs or new_char not in pairs:
            self.message = f"Unknown surround char: {old_char} or {new_char}"
            return
        open_old, close_old = pairs[old_char]
        open_new, close_new = pairs[new_char]
        line = self.lines[self.cy]
        # Find the old pair around cursor
        left = line.rfind(open_old, 0, self.cx + 1)
        right = line.find(close_old, self.cx)
        if left < 0 or right < 0 or left >= right:
            self.message = f"No surrounding {old_char} found"
            return
        self.snapshot()
        # Replace right first (so indices don't shift)
        self.lines[self.cy] = line[:right] + close_new + line[right + 1:]
        self.lines[self.cy] = self.lines[self.cy][:left] + open_new + self.lines[self.cy][left + 1:]
        self.mark_dirty()
        self.message = f"Changed {old_char} → {new_char}"

    def surround_delete(self, char):
        """Delete surrounding pair (ds<char>)."""
        pairs = {
            '(': ('(', ')'), ')': ('(', ')'),
            '[': ('[', ']'), ']': ('[', ']'),
            '{': ('{', '}'), '}': ('{', '}'),
            '<': ('<', '>'), '>': ('<', '>'),
            '"': ('"', '"'), "'": ("'", "'"), '`': ('`', '`'),
        }
        if char not in pairs:
            self.message = f"Unknown surround char: {char}"
            return
        open_ch, close_ch = pairs[char]
        line = self.lines[self.cy]
        left = line.rfind(open_ch, 0, self.cx + 1)
        right = line.find(close_ch, self.cx)
        if left < 0 or right < 0 or left >= right:
            self.message = f"No surrounding {char} found"
            return
        self.snapshot()
        self.lines[self.cy] = line[:right] + line[right + 1:]
        self.lines[self.cy] = self.lines[self.cy][:left] + self.lines[self.cy][left + 1:]
        self.cx = max(0, self.cx - 1)
        self.mark_dirty()
        self.message = f"Deleted surrounding {char}"

    def surround_add(self, char):
        """Add surround around visual selection (ys / S in visual)."""
        pairs = {
            '(': ('(', ')'), ')': ('(', ')'),
            '[': ('[', ']'), ']': ('[', ']'),
            '{': ('{', '}'), '}': ('{', '}'),
            '<': ('<', '>'), '>': ('<', '>'),
            '"': ('"', '"'), "'": ("'", "'"), '`': ('`', '`'),
        }
        if char not in pairs:
            self.message = f"Unknown surround char: {char}"
            return
        if not self.selection:
            self.message = "No selection for surround"
            return
        open_ch, close_ch = pairs[char]
        sy, sx = self.selection
        ey, ex = self.cy, self.cx
        if (sy, sx) > (ey, ex):
            sy, sx, ey, ex = ey, ex, sy, sx
        self.snapshot()
        # Insert close first
        line_e = self.lines[ey]
        self.lines[ey] = line_e[:ex] + close_ch + line_e[ex:]
        # Insert open
        line_s = self.lines[sy]
        self.lines[sy] = line_s[:sx] + open_ch + line_s[sx:]
        self.selection = None
        self.mark_dirty()
        self.message = f"Surrounded with {open_ch}{close_ch}"

    # ── Sort Lines Utility ─────────────────────────────────────────

    def _sort_lines(self):
        """Sort all lines (or selection) alphabetically."""
        self.snapshot()
        if self.selection:
            sy, _ = self.selection
            ey = self.cy
            if sy > ey:
                sy, ey = ey, sy
            self.lines[sy:ey + 1] = sorted(self.lines[sy:ey + 1])
            self.selection = None
        else:
            self.lines.sort()
        self.mark_dirty()
        self.message = "Lines sorted"

    def draw_lsp_diagnostics_gutter(self, stdscr, line_idx, gutter_x, y):
        """Draw LSP diagnostic markers in the gutter."""
        for dline, dcol, severity, dmsg in self.lsp_diagnostics:
            if dline == line_idx:
                marker = "●"
                if severity == 1:
                    attr = curses.color_pair(2) | curses.A_BOLD  # red for error
                elif severity == 2:
                    attr = curses.color_pair(8) | curses.A_BOLD  # yellow for warning
                else:
                    attr = curses.color_pair(5) | curses.A_BOLD  # blue for info
                try:
                    stdscr.addstr(y, gutter_x, marker, attr)
                except curses.error:
                    pass
                return

    def draw_lsp_completion_popup(self, stdscr, height, width):
        """Draw LSP completion popup near the cursor."""
        if not self.lsp_completion_active or not self.lsp_completions:
            return
        tab_h = 1 if self.options.get("tabline") else 0
        top = max(0, self.cy - (max(0, self.cy - height + 4 + tab_h)))
        has_nums = self.options.get("number") or self.options.get("relativenumber")
        prefix_w = (2 if self.git_diff_lines else 0) + (5 if has_nums else 0)
        editor_left = 0
        if self.explorer_visible:
            editor_left = min(self.explorer_width, width // 3)
        popup_x = self.cx + prefix_w + editor_left + 1
        popup_y = top + tab_h + 1
        max_items = min(len(self.lsp_completions), 10, height - popup_y - 3)
        if max_items <= 0:
            return
        popup_w = min(40, width - popup_x - 2)
        if popup_w < 10:
            return
        for i in range(max_items):
            label, detail = self.lsp_completions[i]
            text = label[:popup_w - 2]
            if detail:
                remaining = popup_w - 2 - len(text) - 1
                if remaining > 3:
                    text += " " + detail[:remaining]
            text = text[:popup_w - 2].ljust(popup_w - 2)
            attr = curses.A_REVERSE if i == self.lsp_completion_idx else curses.color_pair(1)
            try:
                stdscr.addstr(popup_y + i, popup_x, " " + text + " ", attr)
            except curses.error:
                pass

    def term_spawn(self, rows=24, cols=80):
        if self.term_fd is not None:
            return
        shell = os.environ.get('SHELL', '/bin/bash')
        pid, fd = pty.openpty()
        # Set initial terminal size so shell/programs know the dimensions
        try:
            fcntl.ioctl(pid, termios.TIOCSWINSZ, struct.pack('HHHH', rows, cols, 0, 0))
        except OSError:
            pass
        try:
            self.term_pid = os.fork()
        except OSError:
            os.close(pid)
            os.close(fd)
            self.message = "Failed to fork terminal"
            return
        if self.term_pid == 0:
            try:
                os.close(pid)
                os.setsid()
                os.dup2(fd, 0)
                os.dup2(fd, 1)
                os.dup2(fd, 2)
                if fd > 2:
                    os.close(fd)
                os.environ['TERM'] = 'dumb'
                os.environ['COLUMNS'] = str(cols)
                os.environ['LINES'] = str(rows)
                os.execvp(shell, [shell, '--noediting'])
            except Exception:
                os._exit(127)
        else:
            os.close(fd)
            self.term_fd = pid
            fl = fcntl.fcntl(self.term_fd, fcntl.F_GETFL)
            fcntl.fcntl(self.term_fd, fcntl.F_SETFL, fl | os.O_NONBLOCK)

    def term_set_size(self, rows, cols):
        if self.term_fd is not None:
            try:
                fcntl.ioctl(self.term_fd, termios.TIOCSWINSZ, struct.pack('HHHH', rows, cols, 0, 0))
            except OSError:
                pass

    def term_read(self):
        if self.term_fd is None:
            return
        try:
            while True:
                r, _, _ = select.select([self.term_fd], [], [], 0)
                if not r:
                    break
                data = os.read(self.term_fd, 4096)
                if not data:
                    self.term_close()
                    return
                text = data.decode('utf-8', errors='replace')
                # Strip ANSI escape sequences (we don't emulate a full VT)
                text = self._ansi_re.sub('', text)
                # Normalize line endings: \r\n -> \n first
                text = text.replace('\r\n', '\n')
                if not self.term_lines:
                    self.term_lines = [""]
                for ch in text:
                    if ch == '\n':
                        self.term_lines.append("")
                        self.term_col = 0
                    elif ch == '\r':
                        # Carriage return: cursor back to column 0
                        self.term_col = 0
                    elif ch == '\x08':  # backspace
                        if self.term_col > 0:
                            self.term_col -= 1
                            line = self.term_lines[-1]
                            if self.term_col < len(line):
                                self.term_lines[-1] = line[:self.term_col] + line[self.term_col + 1:]
                    elif ch == '\x07':  # bell - ignore
                        pass
                    elif ch == '\t':
                        spaces = 8 - (self.term_col % 8)
                        line = self.term_lines[-1]
                        line = line[:self.term_col].ljust(self.term_col) + ' ' * spaces + line[self.term_col + spaces:] if self.term_col < len(line) else line.ljust(self.term_col) + ' ' * spaces
                        self.term_lines[-1] = line
                        self.term_col += spaces
                    elif ord(ch) >= 32 or ch not in '\x00\x01\x02\x03\x04\x05\x06\x0e\x0f\x10\x11\x12\x13\x14\x15\x16\x17\x18\x19\x1a\x1b\x1c\x1d\x1e\x1f':
                        line = self.term_lines[-1]
                        # Overwrite at cursor column
                        if self.term_col < len(line):
                            line = line[:self.term_col] + ch + line[self.term_col + 1:]
                        else:
                            line = line.ljust(self.term_col) + ch
                        self.term_lines[-1] = line
                        self.term_col += 1
                # Auto-scroll to bottom on new output
                self.term_scroll = 0
                # Cap scrollback at 1000 lines
                if len(self.term_lines) > 1000:
                    self.term_lines = self.term_lines[-1000:]
        except OSError:
            pass

    def term_write(self, text):
        if self.term_fd is None:
            return
        try:
            os.write(self.term_fd, text.encode('utf-8'))
        except OSError:
            self.term_close()

    def term_close(self):
        if self.term_fd is not None:
            try:
                os.close(self.term_fd)
            except OSError:
                pass
            self.term_fd = None
        if self.term_pid and self.term_pid > 0:
            import signal
            try:
                os.kill(self.term_pid, signal.SIGHUP)
            except OSError:
                pass
            try:
                os.waitpid(self.term_pid, 0)
            except ChildProcessError:
                pass
            self.term_pid = None

    def term_toggle(self):
        self.term_visible = not self.term_visible
        if self.term_visible:
            self.mode = "terminal"
            self.message = "TERMINAL (Ctrl+n to return)"
        else:
            self.mode = "normal"
            self.message = "EVim - normal mode"

    # ── File Explorer ──────────────────────────────────────────────

    def explorer_build_entries(self):
        """Build the flat list of entries from the directory tree."""
        self.explorer_entries = []
        root = self.explorer_cwd
        self._explorer_scan(root, 0)

    def _explorer_scan(self, dirpath, depth):
        """Recursively scan directory and populate explorer_entries."""
        try:
            items = sorted(os.listdir(dirpath))
        except OSError:
            return
        # Directories first, then files
        dirs = [i for i in items if os.path.isdir(os.path.join(dirpath, i)) and not i.startswith('.')]
        files = [i for i in items if not os.path.isdir(os.path.join(dirpath, i)) and not i.startswith('.')]
        for name in dirs:
            fullpath = os.path.join(dirpath, name)
            expanded = fullpath in self.explorer_expanded
            self.explorer_entries.append((depth, name, fullpath, True, expanded))
            if expanded:
                self._explorer_scan(fullpath, depth + 1)
        for name in files:
            fullpath = os.path.join(dirpath, name)
            self.explorer_entries.append((depth, name, fullpath, False, False))

    def explorer_toggle(self):
        """Toggle the file explorer panel."""
        self.explorer_visible = not self.explorer_visible
        if self.explorer_visible:
            self.explorer_cwd = str(Path.cwd())
            self.explorer_build_entries()
            self.mode = "explorer"
            self.message = "EXPLORER (Ctrl+b to close)"
        else:
            if self.mode == "explorer":
                self.mode = "normal"
                self.message = "EVim - normal mode"

    def explorer_handle_key(self, ch):
        """Handle key input when explorer is focused."""
        if ch in (curses.KEY_EXIT, 27):  # ESC
            self.explorer_visible = False
            self.mode = "normal"
            self.message = "EVim - normal mode"
            return
        entries = self.explorer_entries
        if not entries:
            return
        if ch == curses.KEY_UP or ch == ord('k'):
            self.explorer_cursor = max(0, self.explorer_cursor - 1)
            return
        if ch == curses.KEY_DOWN or ch == ord('j'):
            self.explorer_cursor = min(len(entries) - 1, self.explorer_cursor + 1)
            return
        if ch in (curses.KEY_ENTER, 10, 13, ord('l'), curses.KEY_RIGHT):
            if 0 <= self.explorer_cursor < len(entries):
                depth, name, fullpath, is_dir, expanded = entries[self.explorer_cursor]
                if is_dir:
                    if expanded:
                        self.explorer_expanded.discard(fullpath)
                    else:
                        self.explorer_expanded.add(fullpath)
                    self.explorer_build_entries()
                    # Keep cursor in bounds
                    self.explorer_cursor = min(self.explorer_cursor, len(self.explorer_entries) - 1)
                else:
                    # Open file
                    self.open_buffer(fullpath)
                    self.explorer_visible = False
                    self.mode = "normal"
                    self.message = f"Opened {name}"
            return
        if ch == ord('h') or ch == curses.KEY_LEFT:
            # Collapse directory or go to parent
            if 0 <= self.explorer_cursor < len(entries):
                depth, name, fullpath, is_dir, expanded = entries[self.explorer_cursor]
                if is_dir and expanded:
                    self.explorer_expanded.discard(fullpath)
                    self.explorer_build_entries()
                    self.explorer_cursor = min(self.explorer_cursor, len(self.explorer_entries) - 1)
            return
        if ch == ord('r') or ch == ord('R'):
            self.explorer_build_entries()
            self.message = "Explorer refreshed"
            return

    def draw_file_explorer(self, stdscr, height, width):
        """Draw the file explorer panel on the left side."""
        ew = min(self.explorer_width, width // 3)
        bg = getattr(self, 'color_bg', curses.A_NORMAL)
        border_attr = getattr(self, 'color_status', curses.A_REVERSE)
        # Title bar
        title = " Explorer "
        title_line = title + "─" * max(0, ew - len(title) - 1) + "│"
        try:
            stdscr.addstr(0, 0, title_line[:ew], border_attr)
        except curses.error:
            pass
        # Entries
        entries = self.explorer_entries
        visible_h = height - 3  # title + status + cmdline
        # Auto-scroll to keep cursor visible
        if self.explorer_cursor < self.explorer_scroll:
            self.explorer_scroll = self.explorer_cursor
        if self.explorer_cursor >= self.explorer_scroll + visible_h:
            self.explorer_scroll = self.explorer_cursor - visible_h + 1
        for i in range(visible_h):
            row = i + 1
            eidx = self.explorer_scroll + i
            if row >= height - 2:
                break
            if eidx < len(entries):
                depth, name, fullpath, is_dir, expanded = entries[eidx]
                indent = "  " * depth
                if is_dir:
                    icon = "▼ " if expanded else "▶ "
                else:
                    icon = "  "
                text = indent + icon + name
                attr = bg
                if eidx == self.explorer_cursor and self.mode == "explorer":
                    attr = border_attr
                line_text = text[:ew - 1].ljust(ew - 1) + "│"
            else:
                line_text = " " * (ew - 1) + "│"
                attr = bg
            try:
                stdscr.addstr(row, 0, line_text[:ew], attr)
            except curses.error:
                pass
        return ew

    # ── Minimap ────────────────────────────────────────────────────

    def minimap_toggle(self):
        """Toggle the minimap panel."""
        self.minimap_visible = not self.minimap_visible
        if self.minimap_visible:
            self.message = "Minimap ON"
        else:
            self.message = "Minimap OFF"

    def draw_minimap(self, stdscr, height, width, editor_top):
        """Draw a minimap (code overview) on the right side."""
        mw = min(self.minimap_width, width // 4)
        mx = width - mw
        bg = getattr(self, 'color_bg', curses.A_NORMAL)
        dim_attr = curses.A_DIM | bg
        border_attr = getattr(self, 'color_status', curses.A_REVERSE)
        visible_h = max(1, height - 2)  # rows for minimap content
        total = len(self.lines)
        # Each minimap row represents `ratio` source lines
        if total <= visible_h:
            ratio = 1
        else:
            ratio = max(1, total // visible_h)
        # Title
        title = "│ Map "
        try:
            stdscr.addstr(0, mx, title[:mw], border_attr)
        except curses.error:
            pass
        # Draw compressed lines
        for row in range(1, visible_h):
            src_line_idx = (row - 1) * ratio
            if src_line_idx >= total:
                # Empty row
                try:
                    stdscr.addstr(row, mx, "│" + " " * (mw - 1), dim_attr)
                except curses.error:
                    pass
                continue
            line = self.lines[src_line_idx]
            # Compress: take every other char, show structure
            compressed = ""
            for ci, ch in enumerate(line.replace("\t", " ")):
                if ci >= (mw - 2) * 2:
                    break
                if ci % 2 == 0:
                    if ch == ' ':
                        compressed += ' '
                    elif ch.isalpha():
                        compressed += '░'
                    elif ch.isdigit():
                        compressed += '▒'
                    else:
                        compressed += '·'
            text = "│" + compressed[:mw - 1].ljust(mw - 1)
            # Highlight if this range includes the current cursor line
            attr = dim_attr
            range_start = src_line_idx
            range_end = min(src_line_idx + ratio, total)
            if range_start <= self.cy < range_end:
                attr = border_attr
            # Highlight if in viewport
            elif editor_top <= src_line_idx < editor_top + visible_h:
                attr = curses.A_NORMAL | bg
            try:
                stdscr.addstr(row, mx, text[:mw], attr)
            except curses.error:
                pass
        return mw

    def draw_terminal_panel(self, stdscr):
        height, width = stdscr.getmaxyx()
        # Panel: bottom-right, half width, half height
        panel_h = max(5, height // 2)
        panel_w = max(20, width // 2)
        panel_y = height - panel_h - 2  # above status bar
        panel_x = width - panel_w
        content_w = panel_w - 2  # inside borders
        content_h = panel_h - 2  # inside borders
        # Spawn shell sized to panel if needed
        if self.term_fd is None:
            self.term_spawn(content_h, content_w)
        else:
            self.term_set_size(content_h, content_w)
        bg = getattr(self, 'color_bg', curses.A_NORMAL)
        border_attr = getattr(self, 'color_status', curses.A_REVERSE)
        # Draw border top
        title = " Terminal "
        border_top = "┌" + title + "─" * max(0, panel_w - 2 - len(title)) + "┐"
        try:
            stdscr.addstr(panel_y, panel_x, border_top[:panel_w], border_attr)
        except curses.error:
            pass
        # Read any pending output from the shell
        self.term_read()
        # Draw terminal content lines (shell output includes prompt + typed text)
        if self.term_scroll > 0:
            end = len(self.term_lines) - self.term_scroll
            start = max(0, end - content_h)
            visible = self.term_lines[start:end]
        else:
            visible = self.term_lines[-content_h:]
        for i in range(content_h):
            row = panel_y + 1 + i
            if row >= height - 2:
                break
            text = visible[i] if i < len(visible) else ""
            line_content = "│" + text[:content_w].ljust(content_w) + "│"
            try:
                stdscr.addstr(row, panel_x, line_content[:panel_w], bg)
            except curses.error:
                pass
        # Draw border bottom
        border_bottom = "└" + "─" * max(0, panel_w - 2) + "┘"
        bottom_row = panel_y + panel_h - 1
        if bottom_row < height - 2:
            try:
                stdscr.addstr(bottom_row, panel_x, border_bottom[:panel_w], border_attr)
            except curses.error:
                pass
        # Place cursor at the shell cursor position (end of last visible line)
        if self.mode == "terminal" and self.term_scroll == 0:
            last_line = self.term_lines[-1] if self.term_lines else ""
            cursor_col = min(self.term_col, content_w - 1)
            # Cursor row: position within visible area (panel_y+1 is first content row)
            n_visible = min(len(self.term_lines), content_h)
            cursor_row = panel_y + 1 + n_visible - 1
            if cursor_row < height - 2 and cursor_row >= panel_y + 1:
                curses.setsyx(cursor_row, panel_x + 1 + cursor_col)

    def find_pattern(self, pattern, direction=1):
        if direction == 1:
            for row in range(self.cy, len(self.lines)):
                offset = self.cx + 1 if row == self.cy else 0
                idx = self.lines[row].find(pattern, offset)
                if idx >= 0:
                    return (row, idx)
            for row in range(0, self.cy):
                idx = self.lines[row].find(pattern)
                if idx >= 0:
                    return (row, idx)
        else:
            for row in range(self.cy, -1, -1):
                end = self.cx if row == self.cy else len(self.lines[row])
                idx = self.lines[row].rfind(pattern, 0, end)
                if idx >= 0:
                    return (row, idx)
            for row in range(len(self.lines) - 1, self.cy, -1):
                idx = self.lines[row].rfind(pattern)
                if idx >= 0:
                    return (row, idx)
        return None

    def find_again(self, direction=1):
        if not self.last_search:
            self.message = "No previous search"
            return
        result = self.find_pattern(self.last_search, direction)
        if result:
            self.move_to_search(result)
            self.message = f"Found '{self.last_search}'"
        else:
            self.message = f"Pattern not found: {self.last_search}"

    def move_to_search(self, found):
        self.jumplist_push()
        row, col = found
        self.cy = row
        self.cx = col
        self.set_cursor()

    def set_theme(self, theme_name):
        valid_themes = [
            "classic_blue", "neon_nights", "desert_storm", "sunny_meadow",
            "vampire_castle", "arctic_aurora", "forest_grove", "golden_wheat",
            "midnight_sky", "cloudy_day", "city_lights", "creamy_latte",
            "deep_space", "fresh_breeze", "matrix_code", "ocean_blue",
            "fire_red", "forest_green", "purple_haze", "sunset_orange",
            "arctic_white", "midnight_purple", "desert_gold", "cyber_pink",
        ]
        if theme_name in valid_themes:
            self.options["theme"] = theme_name
            if self.colors_initialized and not self.config_loading:
                self.init_colors()
            self.message = f"Theme set to {theme_name.replace('_', ' ').title()}"
        else:
            self.message = f"Unknown theme: {theme_name}. Available: {', '.join(t.replace('_', ' ').title() for t in valid_themes)}"

    def replace_command(self, command):
        """Handle :s/old/new/, :s/old/new/g, :%s/old/new/g for search & replace"""
        try:
            all_lines = command.startswith("%s/")
            cmd = command[1:] if all_lines else command  # strip leading %
            parts = cmd.split("/")
            if len(parts) < 3:
                self.message = "Use :s/old/new/ or :%s/old/new/g"
                return
            old = parts[1]
            new = parts[2]
            global_flag = len(parts) > 3 and "g" in parts[3]
            self.snapshot()
            total = 0
            if all_lines:
                for i in range(len(self.lines)):
                    if old in self.lines[i]:
                        if global_flag:
                            total += self.lines[i].count(old)
                            self.lines[i] = self.lines[i].replace(old, new)
                        else:
                            total += 1
                            self.lines[i] = self.lines[i].replace(old, new, 1)
            else:
                line = self.current_line()
                if global_flag:
                    total = line.count(old)
                    self.lines[self.cy] = line.replace(old, new)
                else:
                    total = 1 if old in line else 0
                    self.lines[self.cy] = line.replace(old, new, 1)
            if total > 0:
                self.mark_dirty()
                self.message = f"Replaced {total} occurrence(s)"
            else:
                self.message = f"Pattern not found: {old}"
        except Exception as e:
            self.message = f"Replace error: {e}"

    def open_buffer(self, filepath):
        """Open a new file in a buffer"""
        try:
            # Remote SSH: detect user@host:/path syntax
            if "@" in filepath and ":" in filepath:
                self.open_remote(filepath)
                return
            # Save current buffer
            if self.filepath and self.filepath in self.buffers:
                self.buffers[self.filepath] = self.lines[:]
            if filepath not in self.buffers:
                path = Path(filepath)
                if path.exists():
                    text = path.read_text(encoding="utf-8", errors="replace")
                    self.buffers[filepath] = text.splitlines() or [""]
                else:
                    self.buffers[filepath] = [""]
                self.buffer_order.append(filepath)
            self.current_buffer_idx = self.buffer_order.index(filepath)
            self.filepath = filepath
            self.lines = self.buffers[filepath][:]
            self.cx = 0
            self.cy = 0
            self.detect_syntax()
            self.emit("buffer_open", filepath=filepath)
            self._add_recent_file(filepath)
            self.message = f"Opened buffer: {filepath}"
        except Exception as e:
            self.message = f"Error opening buffer: {e}"

    def next_buffer(self):
        """Switch to next buffer (:bn)"""
        if not self.buffer_order:
            self.message = "No buffers open"
            return
        self.current_buffer_idx = (self.current_buffer_idx + 1) % len(self.buffer_order)
        self.filepath = self.buffer_order[self.current_buffer_idx]
        self.lines = self.buffers[self.filepath][:]
        self.cy = min(self.cy, max(0, len(self.lines) - 1))
        self.cx = min(self.cx, max(0, len(self.lines[self.cy]) - 1)) if self.lines[self.cy] else 0
        self.message = f"Buffer: {self.filepath}"

    def prev_buffer(self):
        """Switch to previous buffer (:bp)"""
        if not self.buffer_order:
            self.message = "No buffers open"
            return
        self.current_buffer_idx = (self.current_buffer_idx - 1) % len(self.buffer_order)
        self.filepath = self.buffer_order[self.current_buffer_idx]
        self.lines = self.buffers[self.filepath][:]
        self.cy = min(self.cy, max(0, len(self.lines) - 1))
        self.cx = min(self.cx, max(0, len(self.lines[self.cy]) - 1)) if self.lines[self.cy] else 0
        self.message = f"Buffer: {self.filepath}"

    def list_buffers(self):
        """List all open buffers (:ls, :buffers)"""
        if not self.buffer_order:
            self.message = "No buffers open"
            return
        buf_list = ", ".join(self.buffer_order)
        self.message = f"Buffers: {buf_list}"

    # ── Visual Block Mode ──────────────────────────────────────────────────────

    def toggle_visual_block(self):
        """Enter / toggle visual-block mode (Ctrl+v)."""
        if self.selection_type == "block" and self.selection is not None:
            self.selection = None
            self.selection_type = "char"
            self.message = "EVim - normal mode"
        else:
            self.selection = (self.cy, self.cx)
            self.selection_type = "block"
            self.mode = "visual"
            self.message = "-- VISUAL BLOCK --"

    def _block_selection_rect(self):
        """Return (top_row, bot_row, left_col, right_col) for block selection."""
        if self.selection is None or self.selection_type != "block":
            return None
        sy, sx = self.selection
        ey, ex = self.cy, self.cx
        top = min(sy, ey)
        bot = max(sy, ey)
        left = min(sx, ex)
        right = max(sx, ex)
        return top, bot, left, right

    def delete_block_selection(self):
        """Delete block-selected rectangle."""
        rect = self._block_selection_rect()
        if rect is None:
            return
        top, bot, left, right = rect
        self.snapshot()
        for r in range(top, min(bot + 1, len(self.lines))):
            line = self.lines[r]
            self.lines[r] = line[:left] + line[right + 1:]
        self.cy = top
        self.cx = left
        self.selection = None
        self.selection_type = "char"
        self.mode = "normal"
        self.dirty = True
        self.message = "Block deleted"

    def yank_block_selection(self):
        """Yank block-selected rectangle to clipboard."""
        rect = self._block_selection_rect()
        if rect is None:
            return
        top, bot, left, right = rect
        rows = []
        for r in range(top, min(bot + 1, len(self.lines))):
            line = self.lines[r]
            rows.append(line[left:right + 1])
        self.clipboard = "\n".join(rows)
        self.kill_ring_push(self.clipboard)
        self.selection = None
        self.selection_type = "char"
        self.mode = "normal"
        self.message = f"Block yanked ({len(rows)} lines)"

    def insert_block(self, text):
        """Insert text at every row of the current block column."""
        if self.selection is None or self.selection_type != "block":
            return
        sy, _ = self.selection
        ey = self.cy
        top = min(sy, ey)
        bot = max(sy, ey)
        col = min(self.selection[1], self.cx)
        self.snapshot()
        for r in range(top, min(bot + 1, len(self.lines))):
            line = self.lines[r]
            padded = line.ljust(col)
            self.lines[r] = padded[:col] + text + padded[col:]
        self.dirty = True

    # ── Multi-cursor ──────────────────────────────────────────────────────────

    def multicursor_add(self, cy, cx):
        """Add an extra cursor (Alt+click)."""
        pos = (cy, cx)
        if pos in self.cursors:
            self.cursors.remove(pos)
        else:
            self.cursors.append(pos)
        self.message = f"{len(self.cursors) + 1} cursors"

    def multicursor_clear(self):
        """Clear all extra cursors."""
        self.cursors.clear()
        self.message = "Multi-cursor cleared"

    def _apply_to_all_cursors(self, fn):
        """Run fn(editor, cy, cx) on the primary cursor then all extra cursors."""
        # Primary first
        fn(self, self.cy, self.cx)
        for i, (cy, cx) in enumerate(self.cursors):
            saved_cy, saved_cx = self.cy, self.cx
            self.cy, self.cx = cy, cx
            fn(self, cy, cx)
            self.cursors[i] = (self.cy, self.cx)
            self.cy, self.cx = saved_cy, saved_cx

    # ── Split Panes ───────────────────────────────────────────────────────────

    def split_vertical(self):
        """Split the current window vertically (Ctrl+w v)."""
        pane = {
            "filepath": self.filepath,
            "lines": self.lines[:],
            "cy": self.cy,
            "cx": self.cx,
            "scroll_top": self.scroll_top,
            "scroll_left": self.scroll_left,
            "direction": "v",
        }
        self.splits.append(pane)
        self.active_split = len(self.splits)  # new pane is active
        self.message = f"Vertical split ({len(self.splits) + 1} panes) — Ctrl+w w to switch"

    def split_horizontal(self):
        """Split the current window horizontally (Ctrl+w s)."""
        pane = {
            "filepath": self.filepath,
            "lines": self.lines[:],
            "cy": self.cy,
            "cx": self.cx,
            "scroll_top": self.scroll_top,
            "scroll_left": self.scroll_left,
            "direction": "h",
        }
        self.splits.append(pane)
        self.active_split = len(self.splits)
        self.message = f"Horizontal split ({len(self.splits) + 1} panes) — Ctrl+w w to switch"

    def split_next(self):
        """Focus the next pane (Ctrl+w w)."""
        total = len(self.splits) + 1  # +1 for main editor
        if total < 2:
            self.message = "No splits open"
            return
        # Save current pane state
        if self.active_split == 0:
            pass  # main editor — nothing to save to splits
        else:
            idx = self.active_split - 1
            self.splits[idx]["lines"] = self.lines[:]
            self.splits[idx]["cy"] = self.cy
            self.splits[idx]["cx"] = self.cx
        # Advance
        self.active_split = (self.active_split + 1) % total
        self._split_load_active()

    def split_close(self):
        """Close the active split (Ctrl+w q)."""
        if not self.splits:
            self.message = "No splits to close"
            return
        if self.active_split == 0:
            # Close last split instead
            self.splits.pop()
        else:
            self.splits.pop(self.active_split - 1)
        self.active_split = 0
        self._split_load_active()
        self.message = f"{len(self.splits) + 1} pane(s) remaining"

    def _split_load_active(self):
        """Load the active split's content into the main editor state."""
        if self.active_split == 0:
            # Main editor pane — restore from buffers
            if self.filepath and self.filepath in self.buffers:
                self.lines = self.buffers[self.filepath][:]
            return
        idx = self.active_split - 1
        pane = self.splits[idx]
        self.filepath = pane["filepath"]
        self.lines = pane["lines"][:]
        self.cy = pane["cy"]
        self.cx = pane["cx"]
        self.scroll_top = pane.get("scroll_top", 0)
        self.scroll_left = pane.get("scroll_left", 0)
        self.detect_syntax()

    def _handle_split_key(self, stdscr, next_ch):
        """Handle Ctrl+w <key> combos."""
        if next_ch == ord('v'):
            self.split_vertical()
        elif next_ch == ord('s'):
            self.split_horizontal()
        elif next_ch in (ord('w'), ord('W')):
            self.split_next()
        elif next_ch in (ord('q'), ord('Q')):
            self.split_close()
        elif next_ch == ord('o'):
            # Close all other splits
            self.splits.clear()
            self.active_split = 0
            self.message = "All splits closed"
        else:
            self.message = f"Unknown split command: Ctrl+w {chr(next_ch) if 32 <= next_ch < 127 else '?'}"

    def draw_split_indicators(self, stdscr, height, width):
        """Draw minimal split pane borders/indicators in the status bar."""
        if not self.splits:
            return
        total = len(self.splits) + 1
        indicator = f" [{self.active_split + 1}/{total} panes] "
        attr = getattr(self, 'color_status', curses.A_REVERSE)
        try:
            stdscr.addstr(height - 2, width - len(indicator) - 1, indicator, attr | curses.A_BOLD)
        except curses.error:
            pass

    # ── LSP Code Actions ──────────────────────────────────────────────────────

    def lsp_code_action(self):
        """Request code actions from LSP at the current cursor (Alt+Enter)."""
        if not self.lsp_enabled or not self.lsp_initialized or not self.filepath:
            self.message = "LSP not active"
            return
        diag_here = [
            {"range": {"start": {"line": dl, "character": dc}, "end": {"line": dl, "character": dc + 1}},
             "message": dm, "severity": ds}
            for dl, dc, ds, dm in self.lsp_diagnostics if dl == self.cy
        ]
        rid = self._lsp_send_request("textDocument/codeAction", {
            "textDocument": {"uri": f"file://{os.path.abspath(self.filepath)}"},
            "range": {"start": {"line": self.cy, "character": self.cx},
                      "end": {"line": self.cy, "character": self.cx}},
            "context": {"diagnostics": diag_here, "only": []},
        })
        for _ in range(60):
            with self.lsp_lock:
                if rid in self.lsp_responses:
                    resp = self.lsp_responses.pop(rid)
                    result = resp.get("result", []) or []
                    self.lsp_action_items = []
                    for action in result:
                        title = action.get("title", "Unknown action")
                        cmd = action.get("command")
                        edit = action.get("edit")
                        self.lsp_action_items.append((title, cmd, edit))
                    if self.lsp_action_items:
                        self._show_code_action_picker()
                    else:
                        self.message = "No code actions available"
                    return
            time.sleep(0.02)
        self.message = "LSP: code action timed out"

    def _show_code_action_picker(self):
        """Show a quick-pick for available code actions (reuses palette UI state)."""
        if not self.lsp_action_items:
            return
        # Reuse the palette overlay for displaying actions
        self._palette_visible = True
        self._palette_query = ""
        self._palette_cursor = 0
        # Inject action items as palette entries with a special prefix
        self._palette_items = [
            {"label": f"⚡ {title}", "_lsp_action": (cmd, edit)}
            for title, cmd, edit in self.lsp_action_items
        ]
        self._palette_filtered = list(self._palette_items)
        self.message = "Code actions — Enter to apply, Esc to cancel"

    def _apply_lsp_code_action(self, action_item):
        """Apply a workspace edit from a code action."""
        cmd, edit = action_item.get("_lsp_action", (None, None))
        if edit:
            changes = edit.get("changes", {}) or {}
            doc_changes = edit.get("documentChanges", []) or []
            # Process documentChanges first
            for change in doc_changes:
                if isinstance(change, dict):
                    uri = change.get("textDocument", {}).get("uri", "")
                    fpath = uri.replace("file://", "")
                    edits = change.get("edits", [])
                    self._apply_text_edits(fpath, edits)
            # Then plain changes map
            for uri, edits in changes.items():
                fpath = uri.replace("file://", "")
                self._apply_text_edits(fpath, edits)
            self.message = "Code action applied"
        elif cmd:
            # Execute command on server
            self._lsp_send_request("workspace/executeCommand", {
                "command": cmd.get("command") if isinstance(cmd, dict) else cmd,
                "arguments": cmd.get("arguments", []) if isinstance(cmd, dict) else [],
            })
            self.message = f"Code action sent: {cmd}"
        else:
            self.message = "Empty code action"

    def _apply_text_edits(self, fpath, edits):
        """Apply a list of LSP TextEdits to a file (in reverse order to preserve offsets)."""
        if not fpath:
            return
        abs_path = os.path.abspath(fpath)
        if abs_path == (os.path.abspath(self.filepath) if self.filepath else ""):
            lines = self.lines
        elif fpath in self.buffers:
            lines = self.buffers[fpath]
        else:
            try:
                with open(fpath, encoding="utf-8") as f:
                    lines = f.read().splitlines()
            except OSError:
                return
        # Sort edits in reverse (bottom-up) to keep offsets valid
        sorted_edits = sorted(edits, key=lambda e: (
            e.get("range", {}).get("start", {}).get("line", 0),
            e.get("range", {}).get("start", {}).get("character", 0),
        ), reverse=True)
        for edit in sorted_edits:
            rng = edit.get("range", {})
            s = rng.get("start", {})
            e = rng.get("end", {})
            sl, sc = s.get("line", 0), s.get("character", 0)
            el, ec = e.get("line", 0), e.get("character", 0)
            new_text = edit.get("newText", "")
            # Flatten selection and replace
            if sl >= len(lines):
                continue
            start_line = lines[sl]
            end_line = lines[el] if el < len(lines) else ""
            new_lines = (start_line[:sc] + new_text + end_line[ec:]).split("\n")
            lines[sl:el + 1] = new_lines
        if abs_path == (os.path.abspath(self.filepath) if self.filepath else ""):
            self.lines = lines
            self.dirty = True
        elif fpath in self.buffers:
            self.buffers[fpath] = lines

    # ── LSP Diagnostics Panel ─────────────────────────────────────────────────

    def toggle_diagnostics_panel(self):
        """Toggle the diagnostics panel (:diagnostics)."""
        self._diag_panel_visible = not self._diag_panel_visible
        self._diag_panel_cursor = 0
        if self._diag_panel_visible:
            self.message = "Diagnostics panel — j/k to navigate, Enter to jump, q to close"

    def draw_diagnostics_panel(self, stdscr, height, width):
        """Draw a diagnostics panel at the bottom of the screen."""
        if not self._diag_panel_visible:
            return
        panel_h = min(10, height // 3)
        panel_y = height - 2 - panel_h
        panel_w = width
        # Draw border
        border_attr = getattr(self, 'color_status', curses.A_REVERSE)
        title = " ■ Diagnostics "
        if self.lsp_enabled:
            title += f"({len(self.lsp_diagnostics)} issues) "
        try:
            stdscr.addstr(panel_y, 0, title.ljust(panel_w - 1), border_attr)
        except curses.error:
            pass
        # Draw entries
        diags = sorted(self.lsp_diagnostics, key=lambda d: (d[2], d[0]))  # sort by severity then line
        for i in range(panel_h - 1):
            row = panel_y + 1 + i
            if row >= height - 2:
                break
            idx = i + max(0, self._diag_panel_cursor - panel_h // 2)
            if idx >= len(diags):
                try:
                    stdscr.addstr(row, 0, " " * (panel_w - 1), curses.A_NORMAL)
                except curses.error:
                    pass
                continue
            dl, dc, ds, dm = diags[idx]
            sev_labels = {1: "ERR ", 2: "WARN", 3: "INFO", 4: "HINT"}
            sev_colors = {
                1: getattr(self, 'color_error_lens', curses.color_pair(2) | curses.A_BOLD),
                2: getattr(self, 'color_warn_lens', curses.color_pair(8) | curses.A_BOLD),
                3: getattr(self, 'color_info_lens', curses.color_pair(5)),
                4: curses.A_DIM,
            }
            sev_lbl = sev_labels.get(ds, "?   ")
            sev_attr = sev_colors.get(ds, curses.A_NORMAL)
            is_sel = (idx == self._diag_panel_cursor)
            row_attr = curses.A_REVERSE if is_sel else curses.A_NORMAL
            fname = os.path.basename(self.filepath) if self.filepath else "?"
            line_text = f" {sev_lbl} {fname}:{dl + 1}:{dc + 1}  {dm}"
            line_text = line_text[:panel_w - 1].ljust(panel_w - 1)
            try:
                stdscr.addstr(row, 0, line_text, row_attr)
                # Color the severity label
                stdscr.addstr(row, 1, sev_lbl, sev_attr | (curses.A_REVERSE if is_sel else curses.A_BOLD))
            except curses.error:
                pass

    def handle_diagnostics_panel_key(self, ch):
        """Handle keypresses when the diagnostics panel is focused."""
        diags = sorted(self.lsp_diagnostics, key=lambda d: (d[2], d[0]))
        if ch in (ord('j'), curses.KEY_DOWN):
            self._diag_panel_cursor = min(self._diag_panel_cursor + 1, max(0, len(diags) - 1))
        elif ch in (ord('k'), curses.KEY_UP):
            self._diag_panel_cursor = max(0, self._diag_panel_cursor - 1)
        elif ch in (curses.KEY_ENTER, 10, 13):
            if 0 <= self._diag_panel_cursor < len(diags):
                dl, dc, _, _ = diags[self._diag_panel_cursor]
                self.cy = dl
                self.cx = dc
        elif ch in (ord('q'), 27):
            self._diag_panel_visible = False
            self.message = "EVim - normal mode"

    # ── LSP Inlay Hints ───────────────────────────────────────────────────────

    def lsp_request_inlay_hints(self):
        """Request inlay hints from LSP for the visible range."""
        if not self.lsp_enabled or not self.lsp_initialized or not self.filepath:
            return
        if "inlayHintProvider" not in self.lsp_capabilities:
            return
        rid = self._lsp_send_request("textDocument/inlayHint", {
            "textDocument": {"uri": f"file://{os.path.abspath(self.filepath)}"},
            "range": {
                "start": {"line": max(0, self.cy - 20), "character": 0},
                "end": {"line": min(len(self.lines) - 1, self.cy + 40), "character": 0},
            },
        })
        def _fetch():
            for _ in range(30):
                with self.lsp_lock:
                    if rid in self.lsp_responses:
                        resp = self.lsp_responses.pop(rid)
                        hints = resp.get("result") or []
                        new_hints = {}
                        for h in hints:
                            pos = h.get("position", {})
                            ln = pos.get("line", 0)
                            col = pos.get("character", 0)
                            label = h.get("label", "")
                            if isinstance(label, list):
                                label = "".join(p.get("value", "") for p in label)
                            new_hints.setdefault(ln, []).append((col, label))
                        self.lsp_inlay_hints = new_hints
                        return
                time.sleep(0.05)
        threading.Thread(target=_fetch, daemon=True).start()

    def draw_inlay_hints(self, stdscr, row, lineno, full_prefix_len, x_off, editor_w):
        """Draw inlay hints for a given line (called from redraw)."""
        if not self.options.get("inlay_hints", True):
            return
        hints = self.lsp_inlay_hints.get(lineno, [])
        if not hints:
            return
        hint_attr = curses.A_DIM | getattr(self, 'color_comment', curses.A_DIM)
        for col, label in hints:
            hx = x_off + full_prefix_len + col
            if hx < x_off + editor_w - len(label) - 1:
                try:
                    stdscr.addstr(row, hx, f":{label}", hint_attr)
                except curses.error:
                    pass

    # ── Session Restore ───────────────────────────────────────────────────────

    def session_save(self):
        """Save current session to ~/.config/evim/session.json (:mksession)."""
        self._session_path.parent.mkdir(parents=True, exist_ok=True)
        session = {
            "buffers": self.buffer_order,
            "active": self.filepath,
            "cursors": {fp: (self.cy if fp == self.filepath else 0,
                             self.cx if fp == self.filepath else 0)
                        for fp in self.buffer_order},
            "options": {k: v for k, v in self.options.items() if isinstance(v, (bool, int, str))},
        }
        try:
            with open(self._session_path, "w", encoding="utf-8") as f:
                json.dump(session, f, indent=2)
            self.message = f"Session saved to {self._session_path}"
        except OSError as exc:
            self.message = f"Session save error: {exc}"

    def session_restore(self):
        """Restore session from ~/.config/evim/session.json (:restoresession)."""
        if not self._session_path.exists():
            self.message = "No session file found"
            return
        try:
            with open(self._session_path, encoding="utf-8") as f:
                data = json.load(f)
        except (json.JSONDecodeError, OSError) as exc:
            self.message = f"Session load error: {exc}"
            return
        restored = 0
        for fp in data.get("buffers", []):
            if fp and fp != "[No Name]" and os.path.exists(fp):
                self.open_buffer(fp)
                restored += 1
        active = data.get("active")
        if active and active in self.buffers:
            self.filepath = active
            self.lines = self.buffers[active][:]
            cy, cx = data.get("cursors", {}).get(active, (0, 0))
            self.cy = min(cy, max(0, len(self.lines) - 1))
            self.cx = cx
            self.detect_syntax()
        opts = data.get("options", {})
        for k, v in opts.items():
            self.options[k] = v
        self.message = f"Session restored: {restored} buffers"

    def _session_restore_silent(self):
        """Auto-restore session on startup (no file specified)."""
        if not self._session_path.exists():
            return
        try:
            with open(self._session_path, encoding="utf-8") as f:
                data = json.load(f)
        except Exception:
            return
        for fp in data.get("buffers", []):
            if fp and fp != "[No Name]" and os.path.exists(fp):
                try:
                    self.open_buffer(fp)
                except Exception:
                    pass
        active = data.get("active")
        if active and active in self.buffers:
            self.filepath = active
            self.lines = self.buffers[active][:]
            cy, cx = data.get("cursors", {}).get(active, (0, 0))
            self.cy = min(cy, max(0, len(self.lines) - 1))
            self.cx = cx
            self.detect_syntax()
            self.message = f"Session restored: {os.path.basename(active)}"

    # ── File Watcher ──────────────────────────────────────────────────────────

    def _start_file_watcher(self):
        """Start background thread that watches open buffers for external changes."""
        def _watch():
            while not self.should_exit:
                time.sleep(2)
                for fp in list(self.buffers.keys()):
                    if fp == "[No Name]" or not os.path.exists(fp):
                        continue
                    try:
                        mtime = os.stat(fp).st_mtime
                    except OSError:
                        continue
                    known = self._file_mtimes.get(fp)
                    if known is None:
                        self._file_mtimes[fp] = mtime
                    elif mtime > known + 0.5:
                        self._file_mtimes[fp] = mtime
                        # Only reload if not dirty and not the active file being edited
                        if fp != self.filepath or not self.dirty:
                            try:
                                with open(fp, encoding="utf-8", errors="replace") as f:
                                    new_lines = f.read().splitlines() or [""]
                                self.buffers[fp] = new_lines
                                if fp == self.filepath:
                                    self.lines = new_lines[:]
                                    self.cy = min(self.cy, len(self.lines) - 1)
                                    self.cx = min(self.cx, len(self.lines[self.cy]))
                                    self.message = f"Reloaded: {os.path.basename(fp)}"
                            except OSError:
                                pass
        self._watcher_thread = threading.Thread(target=_watch, daemon=True)
        self._watcher_thread.start()

    # ── Breadcrumbs ───────────────────────────────────────────────────────────

    def update_breadcrumb(self):
        """Update the breadcrumb string from the outline items for the current cursor."""
        if not self._outline_items:
            self._breadcrumb = ""
            return
        # _outline_items are (name, kind, lineno) tuples
        # Find all symbols whose definition line is at or before the cursor
        ancestors = []
        for item in self._outline_items:
            name, kind, lineno = item
            if lineno <= self.cy:
                ancestors.append(name)
            else:
                break
        # Show the last 3 ancestors as breadcrumb
        if ancestors:
            self._breadcrumb = " › ".join(ancestors[-3:])
        else:
            self._breadcrumb = ""

    # ── Git Integration ───────────────────────────────────────────────────────

    def git_command(self, subcmd, args=""):
        """Run a git subcommand and show/store the output."""
        full_cmd = f"git {subcmd} {args}".strip()
        try:
            result = subprocess.run(
                full_cmd, shell=True, capture_output=True, text=True, timeout=15,
                cwd=os.path.dirname(os.path.abspath(self.filepath)) if self.filepath else ".",
            )
            out = (result.stdout or result.stderr or "").strip()
        except subprocess.TimeoutExpired:
            self.message = "git: timed out"
            return
        except Exception as exc:
            self.message = f"git error: {exc}"
            return

        if subcmd in ("status", "log", "diff", "show", "branch", "stash"):
            self._git_status_lines = out.splitlines() or ["(no output)"]
            self._git_status_visible = True
            self._git_status_cursor = 0
            self.message = f"git {subcmd} — j/k to scroll, q to close"
        else:
            # For commit, push, pull, add, etc. just show brief output
            self.message = (out[:200] if out else f"git {subcmd}: done")

    def draw_git_panel(self, stdscr, height, width):
        """Draw the git output panel."""
        if not self._git_status_visible:
            return
        panel_h = min(15, height // 2)
        panel_y = height - 2 - panel_h
        border_attr = getattr(self, 'color_status', curses.A_REVERSE)
        title = " ● git output "
        try:
            stdscr.addstr(panel_y, 0, title.ljust(width - 1), border_attr)
        except curses.error:
            pass
        visible_lines = self._git_status_lines
        offset = max(0, self._git_status_cursor - panel_h // 2)
        for i in range(panel_h - 1):
            row = panel_y + 1 + i
            if row >= height - 2:
                break
            li = offset + i
            if li >= len(visible_lines):
                try:
                    stdscr.addstr(row, 0, " " * (width - 1))
                except curses.error:
                    pass
                continue
            text = visible_lines[li][:width - 1].ljust(width - 1)
            attr = curses.A_REVERSE if li == self._git_status_cursor else curses.A_NORMAL
            # Simple color coding for git status
            if text.lstrip().startswith(("M ", "modified")):
                attr |= getattr(self, 'color_string', curses.A_NORMAL)
            elif text.lstrip().startswith(("A ", "new file")):
                attr |= getattr(self, 'color_keyword', curses.A_NORMAL)
            elif text.lstrip().startswith(("D ", "deleted")):
                attr |= getattr(self, 'color_preprocessor', curses.A_NORMAL)
            elif text.lstrip().startswith("??"):
                attr |= curses.A_DIM
            elif text.startswith("@@"):
                attr |= getattr(self, 'color_type', curses.A_NORMAL)
            elif text.startswith("+"):
                attr |= getattr(self, 'color_keyword', curses.A_NORMAL)
            elif text.startswith("-"):
                attr |= getattr(self, 'color_preprocessor', curses.A_NORMAL)
            try:
                stdscr.addstr(row, 0, text, attr)
            except curses.error:
                pass

    def handle_git_panel_key(self, ch):
        """Handle keys when git panel is visible."""
        if ch in (ord('j'), curses.KEY_DOWN):
            self._git_status_cursor = min(self._git_status_cursor + 1,
                                           max(0, len(self._git_status_lines) - 1))
        elif ch in (ord('k'), curses.KEY_UP):
            self._git_status_cursor = max(0, self._git_status_cursor - 1)
        elif ch in (ord('q'), 27):
            self._git_status_visible = False
            self.message = "EVim - normal mode"
        elif ch in (curses.KEY_ENTER, 10, 13):
            # If cursor is on a file line in status, try to open it
            if 0 <= self._git_status_cursor < len(self._git_status_lines):
                line = self._git_status_lines[self._git_status_cursor]
                # Try to parse file path from git status line
                parts = line.strip().split()
                for part in parts:
                    if os.path.exists(part):
                        self.open_buffer(part)
                        self._git_status_visible = False
                        return

    # ── Remote Editing (SSH) ──────────────────────────────────────────────────

    def open_remote(self, remote_spec):
        """Open a remote file via SCP: user@host:/path/to/file."""
        import shutil
        import tempfile
        if not shutil.which("scp"):
            self.message = "scp not found — install openssh-client"
            return
        # Parse user@host:/path
        if ":" not in remote_spec:
            self.message = f"Invalid remote spec: {remote_spec} (use user@host:/path)"
            return
        host_part, remote_path = remote_spec.split(":", 1)
        # Create a temp file
        suffix = os.path.splitext(remote_path)[1] or ".txt"
        tmp = tempfile.NamedTemporaryFile(suffix=suffix, delete=False)
        tmp_path = tmp.name
        tmp.close()
        self.message = f"Fetching {remote_spec}..."
        try:
            result = subprocess.run(
                ["scp", "-q", f"{host_part}:{remote_path}", tmp_path],
                capture_output=True, text=True, timeout=30,
            )
        except subprocess.TimeoutExpired:
            self.message = "scp: connection timed out"
            os.unlink(tmp_path)
            return
        except Exception as exc:
            self.message = f"scp error: {exc}"
            return
        if result.returncode != 0:
            self.message = f"scp failed: {(result.stderr or '').strip()[:100]}"
            os.unlink(tmp_path)
            return
        # Store remote info so we can push back on save
        self._remote_spec = remote_spec
        self._remote_tmp = tmp_path
        self.open_buffer(tmp_path)
        self.message = f"Remote: {remote_spec} (saved locally at {tmp_path})"

    def push_remote(self):
        """Push current buffer back to the remote server (:wpush)."""
        remote_spec = getattr(self, "_remote_spec", None)
        tmp_path = getattr(self, "_remote_tmp", None)
        if not remote_spec or not tmp_path:
            self.message = "No remote file open"
            return
        # Write local copy first
        self.write_file()
        host_part, remote_path = remote_spec.split(":", 1)
        try:
            result = subprocess.run(
                ["scp", "-q", tmp_path, f"{host_part}:{remote_path}"],
                capture_output=True, text=True, timeout=30,
            )
        except subprocess.TimeoutExpired:
            self.message = "scp push: timed out"
            return
        except Exception as exc:
            self.message = f"scp push error: {exc}"
            return
        if result.returncode == 0:
            self.message = f"Pushed to {remote_spec}"
        else:
            self.message = f"scp push failed: {(result.stderr or '').strip()[:100]}"


def print_usage():
    print("Usage: evim [file]")
    print("  file    File to open (optional, supports user@host:/path for SSH)")
    print("\nKeyboard shortcuts:")
    print("  :help   Show full help inside editor")
    print("  :lsp    Start language server")
    print("  :q      Quit")
    sys.exit(0)

def main():
    import sys
    args = sys.argv[1:]
    filepath = None
    if not args:
        print("you need to provide a file to open, or use -h for help")
        print_usage()

    for arg in args:
        if arg in ("-h", "--help"):
            print_usage()
        elif arg in ("-v", "--version"):
            print("EVim 1.0")
            sys.exit(0)
        elif not arg.startswith("-"):
            filepath = arg
    editor = Editor(filepath)
    curses.wrapper(editor.start)

if __name__ == "__main__":
    main()
