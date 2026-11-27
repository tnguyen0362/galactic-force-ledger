#!/usr/bin/env python3
"""
luau_qa.py — pragmatic static QA for the Galactic Force Luau mirror.

Usage:
    python luau_qa.py <file-or-directory> [...]
    python luau_qa.py --verbose path/to/StarterPlayerScripts path/to/Shared/UI

The checker is intentionally token/regex based rather than a complete Luau parser.  It
is designed to catch regression classes that have repeatedly reached playtests here:

  * locals/functions referenced textually before their declaration
  * missing design-token keys
  * missing UI component/menu-shell APIs
  * client remote references with no server creation/canonical registration
  * banned UICorner usage
  * GF_* workspace attribute reads with no write anywhere in the mirror
  * real luau.exe syntax errors, while ignoring expected runtime noise caused by the
    absence of the Roblox `game` datamodel in the standalone executable

Exit status is 1 when any ERROR finding exists; WARN-only runs exit 0.
"""

from __future__ import annotations

import argparse
import bisect
import concurrent.futures
import os
import re
import subprocess
import sys
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Iterable, Iterator, List, Optional, Sequence, Set, Tuple


# ---------------------------------------------------------------------------
# Basic data structures
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class Finding:
    path: Path
    line: int
    severity: str  # ERROR or WARN
    rule: str
    message: str


@dataclass(frozen=True)
class Token:
    text: str
    line: int
    col: int
    pos: int
    index: int


@dataclass
class Decl:
    name: str
    line: int
    col: int
    scope: "Scope"


@dataclass(frozen=True)
class Use:
    name: str
    line: int
    col: int
    scope: "Scope"
    index: int


class Scope:
    __slots__ = ("kind", "parent", "start_line", "decls", "expecting_do")

    def __init__(self, kind: str, parent: Optional["Scope"], start_line: int) -> None:
        self.kind = kind
        self.parent = parent
        self.start_line = start_line
        self.decls: Dict[str, Decl] = {}
        self.expecting_do = False

    def chain(self) -> Iterator["Scope"]:
        scope: Optional[Scope] = self
        while scope is not None:
            yield scope
            scope = scope.parent


# ---------------------------------------------------------------------------
# Comment/string stripping and tokenization
# ---------------------------------------------------------------------------


def _long_bracket_at(src: str, pos: int) -> Optional[Tuple[int, int, str]]:
    """Return (level, content_start, closing_delimiter) if src[pos] opens a long bracket."""
    if pos >= len(src) or src[pos] != "[":
        return None
    j = pos + 1
    while j < len(src) and src[j] == "=":
        j += 1
    if j < len(src) and src[j] == "[":
        level = j - pos - 1
        return level, j + 1, "]" + ("=" * level) + "]"
    return None


def _blank_range(chars: List[str], start: int, end: int) -> None:
    end = min(end, len(chars))
    for i in range(start, end):
        if chars[i] not in "\r\n":
            chars[i] = " "


def strip_luau(src: str, keep_strings: bool = False) -> str:
    """
    Blank comments (always) and strings (optionally), preserving byte positions and
    line numbers.  This is deliberately small and lexical; it understands Luau long
    strings/comments, quoted strings, and backtick interpolation well enough for QA.
    """
    chars = list(src)
    n = len(src)
    i = 0
    while i < n:
        ch = src[i]

        # Comments.  A long comment is --[[...]] / --[=[...]=] etc.
        if ch == "-" and i + 1 < n and src[i + 1] == "-":
            long_open = _long_bracket_at(src, i + 2) if i + 2 < n else None
            if long_open is not None:
                _level, content_start, closing = long_open
                end_pos = src.find(closing, content_start)
                end = n if end_pos < 0 else end_pos + len(closing)
                _blank_range(chars, i, end)
                i = end
                continue
            end = src.find("\n", i + 2)
            end = n if end < 0 else end
            _blank_range(chars, i, end)
            i = end
            continue

        # Quoted strings and interpolated strings.  Interpolation expressions are
        # intentionally blanked too; this checker favors low-noise lexical scanning.
        if ch in ('"', "'", "`"):
            quote = ch
            j = i + 1
            escaped = False
            while j < n:
                c = src[j]
                if escaped:
                    escaped = False
                elif c == "\\":
                    escaped = True
                elif c == quote:
                    j += 1
                    break
                j += 1
            if not keep_strings:
                _blank_range(chars, i, j)
            i = j
            continue

        # Long strings: [[...]] / [=[...]=]
        if ch == "[":
            long_open = _long_bracket_at(src, i)
            if long_open is not None:
                _level, content_start, closing = long_open
                end_pos = src.find(closing, content_start)
                end = n if end_pos < 0 else end_pos + len(closing)
                if not keep_strings:
                    _blank_range(chars, i, end)
                i = end
                continue

        i += 1

    return "".join(chars)


TOKEN_RE = re.compile(
    r"[A-Za-z_][A-Za-z0-9_]*"
    r"|0[xX][0-9A-Fa-f]+|\d+(?:\.\d*)?(?:[eE][+-]?\d+)?"
    r"|\.\.\.|\.\.|::|->|\+=|-=|\*=|/=|//=|%=|\^=|==|~=|<=|>=|//"
    r"|[+\-*/%^#=<>~;:,.{}\[\]()?|&@$]"
)


def tokenize(code: str) -> List[Token]:
    """Tokenize stripped Luau.  Tokens carry 1-based line/column and absolute pos."""
    tokens: List[Token] = []
    pos = 0
    index = 0
    for line_no, line in enumerate(code.splitlines(keepends=True), 1):
        for match in TOKEN_RE.finditer(line):
            text = match.group(0)
            tokens.append(Token(text, line_no, match.start() + 1, pos + match.start(), index))
            index += 1
        pos += len(line)
    return tokens


def line_starts(src: str) -> List[int]:
    starts = [0]
    for match in re.finditer("\n", src):
        starts.append(match.end())
    return starts


def line_col_at(starts: Sequence[int], offset: int) -> Tuple[int, int]:
    line = bisect.bisect_right(starts, offset)
    return line, offset - starts[line - 1] + 1


def read_text_lossy(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace")


# ---------------------------------------------------------------------------
# Use-before-declaration lexical analysis
# ---------------------------------------------------------------------------


KEYWORDS = {
    "and",
    "break",
    "continue",
    "do",
    "else",
    "elseif",
    "end",
    "false",
    "for",
    "function",
    "if",
    "in",
    "local",
    "nil",
    "not",
    "or",
    "repeat",
    "return",
    "then",
    "true",
    "until",
    "while",
}

IDENT_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
TYPE_STARTERS = {"type"}


def is_ident(text: str) -> bool:
    return bool(IDENT_RE.match(text))


class UseBeforeDeclAnalyzer:
    """
    A small scope-aware lexical scanner.  It is not a Luau compiler; its job is to
    recognize the high-value case where a local is declared later in the same or an
    enclosing lexical scope.  Declarations in sibling blocks do not count.
    """

    def __init__(self, src: str) -> None:
        self.code = strip_luau(src, keep_strings=False)
        self.tokens = tokenize(self.code)
        self.root = Scope("root", None, 1)
        self.stack: List[Scope] = [self.root]
        self.unresolved: List[Use] = []
        self.decl_tokens: Set[int] = set()
        self.usage_skip: Set[int] = set()
        self.if_expr_lines: Set[int] = set()
        self._prepass_type_aliases()

    @property
    def scope(self) -> Scope:
        return self.stack[-1]

    def push(self, kind: str, line: int) -> Scope:
        scope = Scope(kind, self.scope, line)
        self.stack.append(scope)
        return scope

    def pop(self) -> None:
        if len(self.stack) > 1:
            self.stack.pop()

    def declare(self, token: Token, kind: str, scope: Optional[Scope] = None, name: Optional[str] = None) -> None:
        target_scope = scope or self.scope
        decl_name = name or token.text
        self.decl_tokens.add(token.index)
        # Keep the first declaration.  Repeated `local x` in one scope creates a
        # distinct later local, but the first line is the conservative boundary for
        # the use-before-declaration regression this scanner targets.
        if decl_name not in target_scope.decls:
            target_scope.decls[decl_name] = Decl(decl_name, token.line, token.col, target_scope)

    @staticmethod
    def _before(decl: Decl, line: int, col: int) -> bool:
        return (decl.line, decl.col) < (line, col)

    @staticmethod
    def _after(decl: Decl, line: int, col: int) -> bool:
        return (decl.line, decl.col) > (line, col)

    def visible_decl(self, scope: Scope, name: str, line: int, col: int) -> Optional[Decl]:
        for candidate_scope in scope.chain():
            decl = candidate_scope.decls.get(name)
            if decl and self._before(decl, line, col):
                return decl
        return None

    def later_decl(self, scope: Scope, name: str, line: int, col: int) -> Optional[Decl]:
        for candidate_scope in scope.chain():
            decl = candidate_scope.decls.get(name)
            if decl and self._after(decl, line, col):
                return decl
        return None

    def record_use(self, index: int, force: bool = False) -> None:
        if index in self.decl_tokens or (index in self.usage_skip and not force):
            return
        token = self.tokens[index]
        text = token.text
        if not is_ident(text) or text in KEYWORDS or text in TYPE_STARTERS:
            return

        prev_text = self.tokens[index - 1].text if index > 0 else ""
        next_text = self.tokens[index + 1].text if index + 1 < len(self.tokens) else ""

        # Properties and method names are not identifier uses (`x.foo`, `x:foo`).
        if prev_text in (".", ":"):
            return
        # Table constructor keys (`{ key = value }`) are not reads of a variable.
        if next_text == "=" and prev_text in ("{", ","):
            return
        # Type casts use `expr :: Type`; the type name is not a runtime value use.
        if prev_text == "::":
            return

        if self.visible_decl(self.scope, text, token.line, token.col):
            return
        self.unresolved.append(Use(text, token.line, token.col, self.scope, index))

    # ----- type aliases -----------------------------------------------------

    def _prepass_type_aliases(self) -> None:
        """Mark `type X = ...` / `export type X = ...` regions as non-runtime."""
        tokens = self.tokens
        i = 0
        while i < len(tokens):
            start = -1
            if tokens[i].text == "export" and i + 1 < len(tokens) and tokens[i + 1].text == "type":
                start = i
                type_idx = i + 1
            elif tokens[i].text == "type":
                # `type(x)` is the runtime typeof-like function; aliases are
                # `type Name =` or `export type Name =`.
                if i + 2 < len(tokens) and is_ident(tokens[i + 1].text) and tokens[i + 2].text == "=":
                    start = i
                    type_idx = i
                else:
                    i += 1
                    continue
            else:
                i += 1
                continue

            eq_idx = type_idx + 2
            if eq_idx >= len(tokens) or tokens[eq_idx].text != "=":
                i += 1
                continue
            end = self._type_alias_end(eq_idx + 1)
            for idx in range(start, end):
                self.usage_skip.add(idx)
            i = max(end, i + 1)

    def _type_alias_end(self, first_type_token: int) -> int:
        tokens = self.tokens
        if first_type_token >= len(tokens):
            return len(tokens)
        opener = tokens[first_type_token].text
        if opener in ("{", "("):
            closer = "}" if opener == "{" else ")"
            depth = 0
            for idx in range(first_type_token, len(tokens)):
                if tokens[idx].text == opener:
                    depth += 1
                elif tokens[idx].text == closer:
                    depth -= 1
                    if depth == 0:
                        return idx + 1
            return len(tokens)
        # Simple aliases are normally one line.  If a union begins the next line
        # with `|` this deliberately remains incomplete, but runtime-looking noise
        # is still much lower than with no alias handling at all.
        line = tokens[first_type_token].line
        idx = first_type_token
        while idx < len(tokens) and tokens[idx].line == line:
            idx += 1
        return idx

    # ----- declarations -----------------------------------------------------

    def _skip_type_annotation(self, start: int, start_line: int) -> int:
        """Return the first token index after a type annotation."""
        tokens = self.tokens
        depth = 0
        i = start
        while i < len(tokens):
            text = tokens[i].text
            if depth == 0:
                if text in (",", "=", ";"):
                    break
                if tokens[i].line != start_line:
                    # Multiline table/function types are handled by depth.  Union
                    # types are also commonly continued with a leading `|`/`&` on
                    # the next line; other depth-zero line breaks end the declarator.
                    continuation = text in ("|", "&", "?") or (i > start and tokens[i - 1].text in ("|", "&", "->", "."))
                    if not continuation:
                        break
            if text in ("{", "(", "[", "<"):
                depth += 1
            elif text in ("}", ")", "]", ">") and depth > 0:
                depth -= 1
            i += 1
        return i

    def handle_local(self, i: int) -> int:
        tokens = self.tokens
        local_token = tokens[i]
        j = i + 1

        # local function name(...) ... end
        if j < len(tokens) and tokens[j].text == "function":
            name_idx = j + 1
            if name_idx < len(tokens) and is_ident(tokens[name_idx].text):
                self.declare(tokens[name_idx], "local-function")
                return self.handle_function(j, local_name_idx=name_idx)
            return j + 1

        # local a[: T], b[: U] = ...   The declarator is consumed; initializers
        # after `=` remain visible to the normal scanner.
        expect_name = True
        while j < len(tokens):
            token = tokens[j]
            if token.text == "=":
                return j
            if token.text == ";":
                return j + 1
            if token.line != local_token.line:
                return j

            if expect_name:
                if is_ident(token.text) and token.text not in KEYWORDS:
                    self.declare(token, "local")
                    expect_name = False
                else:
                    expect_name = False
            else:
                if token.text == ",":
                    expect_name = True
                elif token.text == ":":
                    j = self._skip_type_annotation(j + 1, token.line)
                    continue
            j += 1
        return j

    def _matching_close(self, open_idx: int, opener: str, closer: str) -> Optional[int]:
        depth = 0
        for idx in range(open_idx, len(self.tokens)):
            text = self.tokens[idx].text
            if text == opener:
                depth += 1
            elif text == closer:
                depth -= 1
                if depth == 0:
                    return idx
        return None

    def _declare_parameters(self, open_idx: int, close_idx: int, fn_scope: Scope) -> None:
        tokens = self.tokens
        # Split the parameter list at commas whose parenthesis depth is exactly the
        # parameter-list depth.  The first identifier in each segment is the name;
        # everything after a colon is a type annotation.
        segment_start = open_idx + 1
        segments: List[Tuple[int, int]] = []
        depth = 1
        for idx in range(open_idx + 1, close_idx):
            text = tokens[idx].text
            if text == "(":
                depth += 1
            elif text == ")":
                depth -= 1
            elif text in ("{", "["):
                depth += 1
            elif text in ("}", "]"):
                depth -= 1
            elif text == "," and depth == 1:
                segments.append((segment_start, idx))
                segment_start = idx + 1
        segments.append((segment_start, close_idx))

        for start, end in segments:
            for idx in range(start, end):
                text = tokens[idx].text
                if text == "...":
                    break
                if is_ident(text) and text not in KEYWORDS:
                    self.declare(tokens[idx], "param", scope=fn_scope)
                    break

    def _consume_balanced_type_delimiter(self, start: int, opener: str, closer: str) -> int:
        depth = 0
        idx = start
        while idx < len(self.tokens):
            text = self.tokens[idx].text
            if text == opener:
                depth += 1
            elif text == closer:
                depth -= 1
                if depth == 0:
                    return idx + 1
            idx += 1
        return start

    def _consume_type_atom(self, start: int) -> int:
        """Consume one pragmatic Luau type atom beginning at token `start`."""
        tokens = self.tokens
        if start >= len(tokens):
            return start
        first = tokens[start].text

        # Table and parenthesized/function types dominate the false-positive risk:
        # their field names (`{ mean: number }`) must never become runtime uses.
        if first == "{":
            end = self._consume_balanced_type_delimiter(start, "{", "}")
        elif first == "(":
            end = self._consume_balanced_type_delimiter(start, "(", ")")
        elif is_ident(first) or first == "nil":
            end = start + 1
            # Dotted type names, optional markers, simple generics, and array suffixes.
            while end < len(tokens):
                text = tokens[end].text
                if text == "." and end + 1 < len(tokens) and is_ident(tokens[end + 1].text):
                    end += 2
                    continue
                if text == "?":
                    end += 1
                    continue
                if text == "<":
                    angle_end = end + 1
                    depth = 1
                    while angle_end < len(tokens) and depth > 0:
                        if tokens[angle_end].text == "<":
                            depth += 1
                        elif tokens[angle_end].text == ">":
                            depth -= 1
                        angle_end += 1
                    if depth == 0:
                        end = angle_end
                        continue
                    break
                if text == "[" and end + 1 < len(tokens) and tokens[end + 1].text == "]":
                    end += 2
                    continue
                break
        else:
            return start

        # Parenthesized type/function-type tails: `(Frame) -> ()`.
        if end < len(tokens) and tokens[end].text == "->":
            tail = self._consume_type_atom(end + 1)
            if tail > end + 1:
                end = tail
        if end < len(tokens) and tokens[end].text == "?":
            end += 1
        return end

    def _type_expression_end(self, start: int) -> int:
        """Return the end of a union/intersection type expression, best effort."""
        end = self._consume_type_atom(start)
        if end == start:
            return start
        while end < len(self.tokens) and self.tokens[end].text in ("|", "&"):
            rhs = self._consume_type_atom(end + 1)
            if rhs <= end + 1:
                break
            end = rhs
        return end

    def handle_function(self, i: int, local_name_idx: Optional[int] = None) -> int:
        tokens = self.tokens
        fn_token = tokens[i]
        j = i + 1
        colon_method = False

        if local_name_idx is not None:
            self.decl_tokens.add(local_name_idx)
            j = local_name_idx + 1
        else:
            # Parse a named function path: function a.b.c(...) / function a:b(...).
            # The member names are not uses; the base of a member assignment is.
            if j < len(tokens) and is_ident(tokens[j].text):
                base_idx = j
                k = j + 1
                member_path = False
                while (
                    k + 1 < len(tokens)
                    and tokens[k].text in (".", ":")
                    and is_ident(tokens[k + 1].text)
                ):
                    member_path = True
                    if tokens[k].text == ":":
                        colon_method = True
                    self.decl_tokens.add(k + 1)
                    k += 2
                if member_path:
                    # `function Components.panel()` requires Components to exist.
                    self.record_use(base_idx)
                # A simple `function foo()` is a global assignment, not a read.
                self.decl_tokens.add(base_idx)
                j = k

        # Find the parameter-list opener.  Luau generic parameters (`<T>`) may sit
        # between the function name and the opener; they are irrelevant here.
        open_idx = -1
        scan = j
        while scan < len(tokens) and scan < j + 80:
            if tokens[scan].text == "(":
                open_idx = scan
                break
            if tokens[scan].text in ("do", "then", "end", "local", "return"):
                break
            scan += 1

        fn_scope = self.push("function", fn_token.line)
        if colon_method:
            # Colon methods receive an implicit self parameter.
            self.declare(fn_token, "param", scope=fn_scope, name="self")

        if open_idx >= 0:
            close_idx = self._matching_close(open_idx, "(", ")")
            if close_idx is not None:
                self._declare_parameters(open_idx, close_idx, fn_scope)
                resume = close_idx + 1
                # Function return annotations are type syntax, not runtime uses.  In
                # particular `{ mean: number }` table-type field names must not be
                # mistaken for forward references to later locals named `mean`.
                if resume < len(tokens) and tokens[resume].text in (":", "->"):
                    type_end = self._type_expression_end(resume + 1)
                    if type_end > resume + 1:
                        for idx in range(resume, type_end):
                            self.usage_skip.add(idx)
                return resume
        return j

    def handle_for(self, i: int) -> None:
        loop_scope = self.push("for", self.tokens[i].line)
        loop_scope.expecting_do = True
        # Declare loop variables before `in` (generic) or `=` (numeric).  The
        # iterable/bound expressions remain normally scanned.
        j = i + 1
        while j < len(self.tokens):
            text = self.tokens[j].text
            if text in ("in", "=", "do"):
                break
            if is_ident(text) and text not in KEYWORDS:
                self.declare(self.tokens[j], "for-var", scope=loop_scope)
            j += 1

    # ----- main scan --------------------------------------------------------

    def is_if_expression(self, index: int) -> bool:
        """Heuristically distinguish Luau `if expr then a else b` from a statement.

        If-expressions do not close with `end`; treating them as block statements
        corrupts every enclosing scope.  The common expression positions are after
        `return`, assignment, opening delimiters, commas, and operators.
        """
        if index <= 0:
            return False
        prev = self.tokens[index - 1].text
        if prev in {
            "return",
            "=",
            "+=",
            "-=",
            "*=",
            "/=",
            "//=",
            "%=",
            "^=",
            "(",
            "{",
            "[",
            ",",
            "and",
            "or",
            "not",
        }:
            return True
        return False

    def scan(self) -> List[Use]:
        tokens = self.tokens
        i = 0
        while i < len(tokens):
            token = tokens[i]
            text = token.text

            if text == "local":
                i = self.handle_local(i)
                continue
            if text == "function":
                i = self.handle_function(i)
                continue
            if text == "for":
                self.handle_for(i)
                i += 1
                continue
            if text == "while":
                scope = self.push("while", token.line)
                scope.expecting_do = True
                i += 1
                continue
            if text == "if":
                is_expr = self.is_if_expression(i) or token.line in self.if_expr_lines
                if is_expr:
                    # Chained `else if ...` branches of one if-expression usually
                    # share the line; remember that line so those branches do not
                    # become phantom block scopes either.
                    self.if_expr_lines.add(token.line)
                else:
                    self.push("if", token.line)
                i += 1
                continue
            if text == "repeat":
                self.push("repeat", token.line)
                i += 1
                continue
            if text == "do":
                consumed = False
                for scope in reversed(self.stack):
                    if scope.expecting_do:
                        scope.expecting_do = False
                        consumed = True
                        break
                if not consumed:
                    self.push("do", token.line)
                i += 1
                continue
            if text == "end":
                self.pop()
                i += 1
                continue
            if text == "until":
                # In Lua the repeat block's scope extends into the until condition.
                # For QA purposes popping here is close enough and keeps nesting sane.
                if self.scope.kind == "repeat":
                    self.pop()
                i += 1
                continue
            if text == "::":
                # Type cast annotations (`value :: Frame`) are type syntax.  Mark
                # the type expression before the scan reaches it so type names do
                # not become imaginary forward references.
                type_end = self._type_expression_end(i + 1)
                if type_end > i + 1:
                    for idx in range(i, type_end):
                        self.usage_skip.add(idx)
                i += 1
                continue

            self.record_use(i)
            i += 1

        return self.unresolved


def check_use_before_decl(path: Path, src: str) -> List[Finding]:
    analyzer = UseBeforeDeclAnalyzer(src)
    uses = analyzer.scan()

    grouped: Dict[Tuple[str, int, int], List[Use]] = defaultdict(list)
    for use in uses:
        decl = analyzer.later_decl(use.scope, use.name, use.line, use.col)
        if decl is not None:
            grouped[(use.name, decl.line, decl.col)].append(use)

    findings: List[Finding] = []
    ordered_groups = sorted(
        grouped.items(),
        key=lambda item: (min(use.line for use in item[1]), item[0][1], item[0][0]),
    )
    for (name, decl_line, _decl_col), group in ordered_groups:
        first = min(group, key=lambda u: (u.line, u.col))
        decl = analyzer.later_decl(first.scope, name, first.line, first.col)
        if decl is None:
            continue
        severity = "ERROR" if decl.scope is analyzer.root else "WARN"
        count_note = f"; {len(group)} uses before the declaration" if len(group) > 1 else ""
        findings.append(
            Finding(
                path,
                first.line,
                severity,
                "use-before-declare",
                f"`{name}` is used before its local declaration on line {decl_line}; "
                f"lexically this resolves as a global/nil rather than the later local{count_note}",
            )
        )
    return findings


# ---------------------------------------------------------------------------
# Project context extraction
# ---------------------------------------------------------------------------


def iter_luau_files(root: Path) -> Iterator[Path]:
    if not root.exists():
        return
    for path in root.rglob("*"):
        if path.is_file() and path.suffix.lower() in (".luau", ".lua"):
            yield path


def extract_braced_block(text: str, open_pos: int) -> Tuple[int, int]:
    """Return positions just after `{` and at its matching `}` using brace count."""
    depth = 0
    for pos in range(open_pos, len(text)):
        ch = text[pos]
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                return open_pos + 1, pos
    return open_pos + 1, len(text)


def extract_tokens_tables(tokens_path: Path) -> Dict[str, Set[str]]:
    """Extract direct keys of every `Tokens.<subtable> = { ... }` table."""
    result: Dict[str, Set[str]] = defaultdict(set)
    if not tokens_path.exists():
        return {}
    src = read_text_lossy(tokens_path)
    code = strip_luau(src, keep_strings=False)

    for match in re.finditer(r"\bTokens\s*\.\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*\{", code):
        subtable = match.group(1)
        open_pos = match.end() - 1
        block_start, block_end = extract_braced_block(code, open_pos)
        block = code[block_start:block_end]
        block_tokens = tokenize(block)
        depth = 0
        for idx, token in enumerate(block_tokens):
            if token.text == "{":
                depth += 1
            elif token.text == "}":
                depth -= 1
            elif depth == 0 and is_ident(token.text):
                # In the slice, top-level table keys have depth zero and are
                # immediately followed by `=`.
                if idx + 1 < len(block_tokens) and block_tokens[idx + 1].text == "=":
                    result[subtable].add(token.text)

    # Token modules sometimes expose compatibility aliases (`Tokens.FactionPalette =
    # Tokens.Faction`).  Preserve those aliases so consumers of either spelling get
    # the same key validation.
    for match in re.finditer(
        r"\bTokens\s*\.\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*Tokens\s*\.\s*([A-Za-z_][A-Za-z0-9_]*)", code
    ):
        alias, target = match.group(1), match.group(2)
        if target in result:
            result[alias].update(result[target])
    return dict(result)


def extract_module_functions(path: Path, table_name: str) -> Set[str]:
    if not path.exists():
        return set()
    code = strip_luau(read_text_lossy(path), keep_strings=False)
    names: Set[str] = set()
    # Canonical methods are usually `function Table.name(...)`.  Aliases and
    # convenience exports may be plain assignments (`Table.alias = Table.real`),
    # so treat every direct Table field assignment as part of the public API too.
    for match in re.finditer(rf"\bfunction\s+{re.escape(table_name)}\s*[\.:]\s*([A-Za-z_][A-Za-z0-9_]*)", code):
        names.add(match.group(1))
    for match in re.finditer(rf"\b{re.escape(table_name)}\s*\.\s*([A-Za-z_][A-Za-z0-9_]*)\s*=", code):
        names.add(match.group(1))
    return names


def extract_remote_registry(remotes_path: Path) -> Tuple[Set[str], Set[str]]:
    if not remotes_path.exists():
        return set(), set()
    text = strip_luau(read_text_lossy(remotes_path), keep_strings=True)

    def one(table: str) -> Set[str]:
        match = re.search(rf"\bRemotes\s*\.\s*{table}\s*=\s*\{{", text)
        if not match:
            return set()
        start, end = extract_braced_block(text, match.end() - 1)
        return set(re.findall(r"['\"]([A-Za-z_][A-Za-z0-9_]*)['\"]", text[start:end]))

    return one("Names"), one("Functions")


REMOTE_INSTANCE_RE = re.compile(r"Instance\s*\.\s*new\s*\(\s*['\"]Remote(?:Event|Function)['\"]\s*\)")
REMOTE_NAME_ASSIGN_RE = re.compile(r"\.\s*Name\s*=\s*['\"]([A-Za-z_][A-Za-z0-9_]*)['\"]")
REMOTE_HELPER_CALL_RE = re.compile(
    r"\b(?:ensure|create|make)[A-Za-z0-9_]*Remote[A-Za-z0-9_]*\s*\(\s*['\"]([A-Za-z_][A-Za-z0-9_]*)['\"]",
    re.IGNORECASE,
)


class ProjectContext:
    def __init__(self, mirror: Path) -> None:
        self.mirror = mirror
        self.ui_dir = mirror / "ReplicatedStorage" / "GF" / "Shared" / "UI"
        self.remotes_path = mirror / "ReplicatedStorage" / "GF" / "Shared" / "Remotes.luau"
        self.server_root = mirror / "ServerScriptService"
        self.client_root = mirror / "StarterPlayer" / "StarterPlayerScripts"

        self.token_keys = extract_tokens_tables(self.ui_dir / "Tokens.luau")
        self.component_functions = extract_module_functions(self.ui_dir / "Components.luau", "Components")
        self.menushell_methods = extract_module_functions(self.ui_dir / "MenuShell.luau", "MenuShell")
        self.remote_events, self.remote_functions = extract_remote_registry(self.remotes_path)
        self.canonical_remotes = set(self.remote_events) | set(self.remote_functions)
        self.server_created_remotes, self.canonical_creation_evidence = self.scan_server_remotes()
        self.attr_writes, self.attr_prefix_writes = self.scan_attribute_writes()

    def scan_server_remotes(self) -> Tuple[Set[str], bool]:
        created: Set[str] = set()
        canonical_event_loop = False
        canonical_function_loop = False
        if not self.server_root.exists():
            return created, False

        for path in iter_luau_files(self.server_root):
            try:
                code = strip_luau(read_text_lossy(path), keep_strings=True)
            except OSError:
                continue
            for match in REMOTE_INSTANCE_RE.finditer(code):
                window = code[match.end() : match.end() + 300]
                name_match = REMOTE_NAME_ASSIGN_RE.search(window)
                if name_match:
                    created.add(name_match.group(1))
            for match in REMOTE_HELPER_CALL_RE.finditer(code):
                created.add(match.group(1))

            if re.search(r"\bfor\s+[^\n]+\bin\s+Remotes\s*\.\s*Names\b", code) and "RemoteEvent" in code:
                canonical_event_loop = True
            if re.search(r"\bfor\s+[^\n]+\bin\s+Remotes\s*\.\s*Functions\b", code) and "RemoteFunction" in code:
                canonical_function_loop = True

        if canonical_event_loop:
            created.update(self.remote_events)
        if canonical_function_loop:
            created.update(self.remote_functions)
        return created, canonical_event_loop and canonical_function_loop

    def scan_attribute_writes(self) -> Tuple[Set[str], Set[str]]:
        exact: Set[str] = set()
        prefixes: Set[str] = set()
        if not self.mirror.exists():
            return exact, prefixes
        pattern = re.compile(r":\s*SetAttribute\s*\(\s*(['\"])(GF_[A-Za-z0-9_]*)\1(\s*\.\.)?")
        for path in iter_luau_files(self.mirror):
            try:
                code = strip_luau(read_text_lossy(path), keep_strings=True)
            except OSError:
                continue
            for match in pattern.finditer(code):
                key = match.group(2)
                if match.group(3):
                    prefixes.add(key)
                else:
                    exact.add(key)
        return exact, prefixes

    def attr_is_written(self, name: str) -> bool:
        if name in self.attr_writes:
            return True
        # Dynamic writes such as `"GF_Equipped_" .. userId` cannot prove a given
        # exact key, but they are useful evidence.  Require a reasonably specific
        # prefix so `GF_` alone does not suppress every warning.
        return any(len(prefix) >= 10 and name.startswith(prefix) for prefix in self.attr_prefix_writes)


# ---------------------------------------------------------------------------
# Focused static checks
# ---------------------------------------------------------------------------


def module_aliases(code_with_strings: str, module_name: str, default_alias: Optional[str] = None) -> Set[str]:
    aliases: Set[str] = set()
    if default_alias:
        aliases.add(default_alias)
    require_re = re.compile(r"\blocal\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*require\s*\((.*)")
    for line in code_with_strings.splitlines():
        match = require_re.search(line)
        if match and re.search(rf"(?<![A-Za-z0-9_]){re.escape(module_name)}(?![A-Za-z0-9_])", match.group(2)):
            aliases.add(match.group(1))
    return aliases


def check_tokens_api(path: Path, src: str, ctx: ProjectContext) -> List[Finding]:
    if not any(ctx.token_keys.values()):
        return []
    code_strings = strip_luau(src, keep_strings=True)
    code = strip_luau(src, keep_strings=False)
    aliases = module_aliases(code_strings, "Tokens", "Tokens")
    tokens = tokenize(code)
    findings: List[Finding] = []
    seen: Set[Tuple[str, str, int]] = set()

    alias_alts = sorted((re.escape(a) for a in aliases), key=len, reverse=True)
    if not alias_alts:
        return findings
    alias_set = set(aliases)
    for idx, token in enumerate(tokens[:-4]):
        if token.text not in alias_set:
            continue
        if tokens[idx + 1].text != ".":
            continue
        subtable = tokens[idx + 2].text
        if subtable not in ctx.token_keys:
            continue
        if tokens[idx + 3].text != "." or not is_ident(tokens[idx + 4].text):
            continue
        key = tokens[idx + 4].text
        if key not in ctx.token_keys[subtable]:
            dedupe_key = (subtable, key, token.line)
            if dedupe_key in seen:
                continue
            seen.add(dedupe_key)
            findings.append(
                Finding(
                    path,
                    token.line,
                    "ERROR",
                    "tokens-missing-key",
                    f"Tokens.{subtable}.{key} is not defined in Shared/UI/Tokens.luau",
                )
            )
    return findings


def check_components_api(path: Path, src: str, ctx: ProjectContext) -> List[Finding]:
    if not ctx.component_functions:
        return []
    code_strings = strip_luau(src, keep_strings=True)
    code = strip_luau(src, keep_strings=False)
    aliases = module_aliases(code_strings, "Components", "Components")
    tokens = tokenize(code)
    findings: List[Finding] = []
    seen: Set[Tuple[str, int]] = set()
    for idx, token in enumerate(tokens[:-2]):
        if token.text not in aliases or tokens[idx + 1].text != ".":
            continue
        member = tokens[idx + 2].text
        if not is_ident(member):
            continue
        if member not in ctx.component_functions:
            key = (member, token.line)
            if key in seen:
                continue
            seen.add(key)
            findings.append(
                Finding(
                    path,
                    token.line,
                    "ERROR",
                    "components-missing-api",
                    f"Components.{member} is not defined in Shared/UI/Components.luau",
                )
            )
    return findings


def check_menushell_api(path: Path, src: str, ctx: ProjectContext) -> List[Finding]:
    if not ctx.menushell_methods:
        return []
    code_strings = strip_luau(src, keep_strings=True)
    code = strip_luau(src, keep_strings=False)
    aliases = module_aliases(code_strings, "MenuShell", "MenuShell")
    tokens = tokenize(code)

    shell_vars: Set[str] = set()
    for alias in aliases:
        creation_re = re.compile(
            rf"\b(?:local\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*{re.escape(alias)}\s*\.\s*new\s*\("
        )
        for match in creation_re.finditer(code_strings):
            shell_vars.add(match.group(1))

    # The project convention uses `shell` for MenuShell instances.  Only apply that
    # convention when MenuShell/MenuController evidence exists, so server variables
    # named shell (projectile shells, station instances) do not false-positive.
    if (
        "shell" in code_strings
        and ("MenuShell" in code_strings or "MenuController" in code_strings or path.name in {"MenuShell.luau", "MenuController.luau"})
    ):
        shell_vars.add("shell")
    if path.name == "MenuShell.luau":
        shell_vars.add("self")

    findings: List[Finding] = []
    seen: Set[Tuple[str, int]] = set()
    for idx, token in enumerate(tokens[:-3]):
        if token.text not in shell_vars or tokens[idx + 1].text != ":":
            continue
        method = tokens[idx + 2].text
        if not is_ident(method) or tokens[idx + 3].text != "(":
            continue
        if method not in ctx.menushell_methods:
            key = (method, token.line)
            if key in seen:
                continue
            seen.add(key)
            findings.append(
                Finding(
                    path,
                    token.line,
                    "ERROR",
                    "menushell-missing-method",
                    f"MenuShell method `{method}` is not defined in Shared/UI/MenuShell.luau",
                )
            )
    return findings


def check_uicorner(path: Path, src: str) -> List[Finding]:
    code = strip_luau(src, keep_strings=True)
    starts = line_starts(code)
    findings: List[Finding] = []
    for match in re.finditer(r"\bInstance\s*\.\s*new\s*\(\s*['\"]UICorner['\"]", code):
        line, _col = line_col_at(starts, match.start())
        findings.append(
            Finding(
                path,
                line,
                "WARN",
                "uicorner-banned",
                "UICorner is banned by the angular GF UI design language; use strokes/brackets/chamfers instead",
            )
        )
    return findings


def is_clientish_path(path: Path) -> bool:
    parts = {part.lower() for part in path.parts}
    return "starterplayerscripts" in parts or "replicatedstorage" in parts


def remote_folder_variables(code_with_strings: str) -> Set[str]:
    """Find variables assigned the GF.Remotes folder (not merely the GF folder).

    This remains heuristic rather than flow-sensitive, but two shapes are important:
    `x = ReplicatedStorage.GF.Remotes` and `x = ...:WaitForChild("Remotes")` are
    folders, while `x = ReplicatedStorage.GF.Remotes:FindFirstChild("Foo")` is a
    remote object and must not make the following `.OnClientEvent` look like a
    remote named OnClientEvent.
    """
    result: Set[str] = set()
    assign_re = re.compile(r"(?:^|[;\s])(?:local\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)")
    child_re = re.compile(r"(?:WaitForChild|FindFirstChild)\s*\(\s*['\"]([A-Za-z_][A-Za-z0-9_]*)['\"]")
    for line in code_with_strings.splitlines():
        match = assign_re.search(line)
        if not match:
            continue
        var, rhs = match.group(1), match.group(2)
        child_names = child_re.findall(rhs)
        if child_names:
            if child_names[-1] == "Remotes":
                result.add(var)
            continue
        # Direct `.GF.Remotes` with no further member/child access on the RHS.
        if re.search(r"\.\s*GF\s*\.\s*Remotes\s*$", rhs):
            result.add(var)
    return result


def extract_remote_references(path: Path, src: str) -> List[Tuple[str, int]]:
    code_strings = strip_luau(src, keep_strings=True)
    starts = line_starts(code_strings)
    refs: List[Tuple[str, int]] = []
    folder_vars = remote_folder_variables(code_strings)

    # String child lookups on remote-folder variables.
    for var in sorted(folder_vars, key=len, reverse=True):
        pattern = re.compile(
            rf"\b{re.escape(var)}\s*:\s*(?:FindFirstChild|WaitForChild)\s*\(\s*['\"]([A-Za-z_][A-Za-z0-9_]*)['\"]"
        )
        for match in pattern.finditer(code_strings):
            # `"Remotes"` here is the folder lookup itself, not a remote reference.
            if match.group(1) == "Remotes":
                continue
            line, _ = line_col_at(starts, match.start(1))
            refs.append((match.group(1), line))

    # Inline ReplicatedStorage.GF.Remotes:FindFirstChild/WaitForChild chains.
    inline_re = re.compile(
        r"\.\s*GF\s*\.\s*Remotes\s*:\s*(?:FindFirstChild|WaitForChild)\s*\(\s*['\"]([A-Za-z_][A-Za-z0-9_]*)['\"]"
    )
    for match in inline_re.finditer(code_strings):
        line, _ = line_col_at(starts, match.start(1))
        refs.append((match.group(1), line))

    # Inline direct property chains: ReplicatedStorage.GF.Remotes.RequestX.
    inline_property_re = re.compile(r"\.\s*GF\s*\.\s*Remotes\s*\.\s*([A-Z][A-Za-z0-9_]*)")
    for match in inline_property_re.finditer(code_strings):
        line, _ = line_col_at(starts, match.start(1))
        refs.append((match.group(1), line))

    # Canonical registry accessors, when scripts use the typed contract module.
    registry_re = re.compile(r"\bRemotes\s*\.\s*(?:get|server|func)\s*\(\s*['\"]([A-Za-z_][A-Za-z0-9_]*)['\"]")
    for match in registry_re.finditer(code_strings):
        line, _ = line_col_at(starts, match.start(1))
        refs.append((match.group(1), line))

    # Property-style access (`remotes.FireWeapon`) on variables proven to point at
    # the remote folder.  Strings are blanked here; comments are already stripped.
    code_no_strings = strip_luau(src, keep_strings=False)
    tokens = tokenize(code_no_strings)
    non_remote_members = {
        "Names",
        "Functions",
        "ContractVersion",
        "OnClientEvent",
        "OnServerEvent",
        "FireServer",
        "InvokeServer",
        "IsA",
        "Name",
        "Parent",
    }
    for idx, token in enumerate(tokens[:-2]):
        if token.text in folder_vars and tokens[idx + 1].text == ".":
            name = tokens[idx + 2].text
            if is_ident(name) and name[:1].isupper() and name not in non_remote_members:
                refs.append((name, token.line))

    # De-duplicate exact line/name pairs while preserving order.
    out: List[Tuple[str, int]] = []
    seen: Set[Tuple[str, int]] = set()
    for name, line in refs:
        key = (name, line)
        if key not in seen:
            seen.add(key)
            out.append((name, line))
    return out


def check_remote_drift(path: Path, src: str, ctx: ProjectContext) -> List[Finding]:
    if not is_clientish_path(path):
        return []
    refs = extract_remote_references(path, src)
    by_name: Dict[str, List[int]] = defaultdict(list)
    for name, line in refs:
        by_name[name].append(line)

    findings: List[Finding] = []
    for name, lines in sorted(by_name.items(), key=lambda item: min(item[1])):
        first = min(lines)
        count_note = f" ({len(lines)} references)" if len(lines) > 1 else ""
        if name in ctx.canonical_remotes:
            if name not in ctx.server_created_remotes:
                findings.append(
                    Finding(
                        path,
                        first,
                        "WARN",
                        "remote-registered-not-created",
                        f"remote `{name}` is in Shared/Remotes.luau but no server-side creation was found{count_note}",
                    )
                )
            continue
        if name in ctx.server_created_remotes:
            findings.append(
                Finding(
                    path,
                    first,
                    "WARN",
                    "remote-unregistered-adhoc",
                    f"remote `{name}` is created ad hoc server-side but missing from Shared/Remotes.luau{count_note}",
                )
            )
        else:
            findings.append(
                Finding(
                    path,
                    first,
                    "ERROR",
                    "remote-missing",
                    f"client references remote `{name}`, but it is neither registered in Shared/Remotes.luau nor created server-side{count_note}",
                )
            )
    return findings


def check_workspace_attrs(path: Path, src: str, ctx: ProjectContext) -> List[Finding]:
    code = strip_luau(src, keep_strings=True)
    starts = line_starts(code)
    # Only exact literal keys are checkable.  Dynamic keys such as
    # `GetAttribute("GF_WarState_" .. region .. "_Status")` deliberately do not
    # produce findings: the static prefix is not itself an attribute name.
    read_re = re.compile(r"\b(?:workspace|Workspace)\s*:\s*GetAttribute\s*\(\s*['\"](GF_[A-Za-z0-9_]*)['\"]\s*\)")
    by_name: Dict[str, List[int]] = defaultdict(list)
    for match in read_re.finditer(code):
        line, _ = line_col_at(starts, match.start(1))
        by_name[match.group(1)].append(line)

    findings: List[Finding] = []
    for name, lines in sorted(by_name.items(), key=lambda item: min(item[1])):
        if ctx.attr_is_written(name):
            continue
        count_note = f" ({len(lines)} reads)" if len(lines) > 1 else ""
        findings.append(
            Finding(
                path,
                min(lines),
                "WARN",
                "workspace-attr-unwritten",
                f"workspace:GetAttribute(\"{name}\") has no matching SetAttribute write in this mirror{count_note}; may be cross-place/external",
            )
        )
    return findings


# ---------------------------------------------------------------------------
# luau.exe syntax checking
# ---------------------------------------------------------------------------


COMPILE_ERROR_RE = re.compile(
    r"^(?:"
    r"Expected\b|Unexpected\b|Malformed\b|Incomplete statement\b|Unterminated\b|"
    r"Invalid escape\b|Invalid unicode\b|Syntax error\b|Ambiguous\b"
    r")",
    re.IGNORECASE,
)

# Runtime/compiler discrimination is structural (empty vs populated stacktrace),
# not a regex over runtime error prose, because games can raise arbitrary messages.
DIAGNOSTIC_RE = re.compile(r"^(?P<file>.+?):(?P<line>\d+):(?P<msg>.*)$")
STACK_FRAME_LOCATION_RE = re.compile(r"^.+?:\d+$")


def classify_luau_output(path: Path, output: str) -> List[Finding]:
    findings: List[Finding] = []
    lines = [raw.strip("\r") for raw in output.splitlines()]

    for line_index, line in enumerate(lines):
        if not line or line == "stacktrace:":
            continue
        match = DIAGNOSTIC_RE.match(line)
        if not match:
            continue
        msg = match.group("msg").strip()
        if not msg:
            continue
        try:
            line_no = int(match.group("line"))
        except ValueError:
            line_no = 0

        # Structural distinction learned from the standalone executable: parse
        # failures print `file:line: message` followed by an empty `stacktrace:`;
        # runtime failures have `[C] ...` frames and/or `file:line` frames below
        # the stacktrace header.  The wording check handles known compiler errors,
        # while the empty-stacktrace fallback future-proofs new compiler wording.
        subsequent = lines[line_index + 1 :]
        has_runtime_frame = any(
            frame_line.startswith("[C]") or STACK_FRAME_LOCATION_RE.match(frame_line or "") is not None
            for frame_line in subsequent
            if frame_line and frame_line != "stacktrace:"
        )
        compile_like = COMPILE_ERROR_RE.match(msg) is not None
        if compile_like or not has_runtime_frame:
            findings.append(Finding(path, line_no, "ERROR", "syntax", msg))
            continue

        # Anything with execution frames is runtime noise in this environment:
        # standalone luau.exe has no Roblox datamodel, so `game`, `script`, Color3,
        # Enum, and service access can all fail after a successful parse.
        continue
    return findings


def check_syntax_with_luau(path: Path, luau_exe: Path, timeout: float) -> Tuple[List[Finding], Optional[str]]:
    if not luau_exe.exists():
        return [Finding(path, 0, "WARN", "syntax-tool-missing", f"luau.exe not found at {luau_exe}")], "missing"
    try:
        proc = subprocess.run(
            [str(luau_exe), str(path)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        # A timeout means compilation finished and top-level execution began (or a
        # test script is spinning).  Syntax errors terminate quickly before execution.
        return [], "timeout"
    except OSError as exc:
        return [Finding(path, 0, "WARN", "syntax-tool-error", f"could not run luau.exe: {exc}")], "error"

    # luau.exe writes compiler/runtime diagnostics to stderr.  stdout is script
    # output and including it can only confuse the frame heuristic when a program
    # printed before hitting a runtime error.
    output = proc.stderr if proc.stderr else (proc.stdout or "")
    return classify_luau_output(path, output), None


# ---------------------------------------------------------------------------
# File collection, orchestration, and output
# ---------------------------------------------------------------------------


def collect_input_files(inputs: Sequence[Path]) -> List[Path]:
    files: List[Path] = []
    seen: Set[Path] = set()
    for input_path in inputs:
        path = input_path.resolve()
        if path.is_file() and path.suffix.lower() in (".luau", ".lua"):
            candidates = [path]
        elif path.is_dir():
            candidates = sorted(iter_luau_files(path))
        else:
            candidates = []
        for candidate in candidates:
            resolved = candidate.resolve()
            if resolved not in seen:
                seen.add(resolved)
                files.append(resolved)
    return sorted(files, key=lambda p: str(p).lower())


def detect_mirror(inputs: Sequence[Path], explicit: Optional[Path], script_path: Path) -> Path:
    if explicit:
        return explicit.resolve()
    for input_path in inputs:
        resolved = input_path.resolve()
        start = resolved if resolved.is_dir() else resolved.parent
        for candidate in (start, *start.parents):
            if (candidate / "ReplicatedStorage" / "GF" / "Shared" / "UI" / "Tokens.luau").exists() and (
                candidate / "ServerScriptService"
            ).exists():
                return candidate
    return (script_path.resolve().parent.parent / "game-mirror" / "playtest1_current").resolve()


def analyze_file(path: Path, ctx: ProjectContext, luau_exe: Path, syntax_timeout: float, no_syntax: bool) -> Tuple[List[Finding], Optional[str]]:
    try:
        src = read_text_lossy(path)
    except OSError as exc:
        return [Finding(path, 0, "ERROR", "read-error", f"could not read file: {exc}")], None

    findings: List[Finding] = []
    findings.extend(check_use_before_decl(path, src))
    findings.extend(check_tokens_api(path, src, ctx))
    findings.extend(check_components_api(path, src, ctx))
    findings.extend(check_menushell_api(path, src, ctx))
    findings.extend(check_uicorner(path, src))
    findings.extend(check_remote_drift(path, src, ctx))
    findings.extend(check_workspace_attrs(path, src, ctx))

    syntax_note: Optional[str] = None
    if not no_syntax:
        syntax_findings, syntax_note = check_syntax_with_luau(path, luau_exe, syntax_timeout)
        findings.extend(syntax_findings)

    findings.sort(key=lambda f: (f.line, f.rule, f.message))
    return findings, syntax_note


def display_path(path: Path, base: Path) -> str:
    try:
        return str(path.relative_to(base))
    except ValueError:
        return str(path)


def print_report(
    all_findings: Dict[Path, List[Finding]],
    files: Sequence[Path],
    base: Path,
    verbose: bool,
    syntax_notes: Dict[Path, str],
) -> None:
    for path in files:
        findings = all_findings.get(path, [])
        shown_path = display_path(path, base)
        if not findings:
            if verbose:
                note = syntax_notes.get(path)
                suffix = f" (luau syntax subprocess {note})" if note else ""
                print(f"OK {shown_path}{suffix}")
            continue
        print(shown_path)
        for finding in findings:
            location = f":{finding.line}" if finding.line else ""
            print(f"  {finding.severity}{location} [{finding.rule}] {finding.message}")

    total_errors = sum(1 for findings in all_findings.values() for f in findings if f.severity == "ERROR")
    total_warnings = sum(1 for findings in all_findings.values() for f in findings if f.severity == "WARN")
    files_with_findings = sum(1 for findings in all_findings.values() if findings)
    clean_files = len(files) - files_with_findings
    print(
        f"SUMMARY: files={len(files)} errors={total_errors} warnings={total_warnings} "
        f"files_with_findings={files_with_findings} clean_files={clean_files}"
    )


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Pragmatic static QA for Galactic Force Luau files",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument("paths", nargs="+", type=Path, help="Luau files or directories to scan")
    parser.add_argument("--verbose", action="store_true", help="show clean files, context counts, and syntax subprocess notes")
    parser.add_argument("--mirror", type=Path, help="playtest mirror root used for cross-file context")
    parser.add_argument(
        "--luau",
        type=Path,
        default=Path(r"C:\Users\tnguy\gf-research\tools\luau.exe"),
        help="path to standalone luau.exe",
    )
    parser.add_argument("--syntax-timeout", type=float, default=5.0, help="seconds allowed for each luau.exe run")
    parser.add_argument("--no-syntax", action="store_true", help="skip luau.exe subprocess syntax checks")
    parser.add_argument("--jobs", type=int, default=max(2, min(8, (os.cpu_count() or 4))), help="parallel file-analysis workers")
    return parser


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = build_arg_parser()
    args = parser.parse_args(argv)

    files = collect_input_files(args.paths)
    if not files:
        print("SUMMARY: files=0 errors=0 warnings=0 files_with_findings=0 clean_files=0")
        print("WARNING: no .luau/.lua files matched the supplied paths", file=sys.stderr)
        return 0

    mirror = detect_mirror(args.paths, args.mirror, Path(__file__))
    ctx = ProjectContext(mirror)

    if args.verbose:
        print(f"CONTEXT: mirror={mirror}")
        print(
            "CONTEXT: "
            f"tokens={sum(len(v) for v in ctx.token_keys.values())} "
            f"components={len(ctx.component_functions)} "
            f"menushell_methods={len(ctx.menushell_methods)} "
            f"canonical_remotes={len(ctx.canonical_remotes)} "
            f"server_created_remotes={len(ctx.server_created_remotes)} "
            f"workspace_attr_writes={len(ctx.attr_writes)}"
        )
        if not ctx.canonical_creation_evidence:
            print("CONTEXT WARNING: no complete RemoteService canonical creation loop detected")

    all_findings: Dict[Path, List[Finding]] = {}
    syntax_notes: Dict[Path, str] = {}
    workers = max(1, args.jobs)
    with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as executor:
        future_map = {
            executor.submit(analyze_file, path, ctx, args.luau, args.syntax_timeout, args.no_syntax): path for path in files
        }
        for future in concurrent.futures.as_completed(future_map):
            path = future_map[future]
            try:
                findings, note = future.result()
            except Exception as exc:  # harness robustness: report, do not hide behind a crash
                findings, note = [Finding(path, 0, "ERROR", "harness-error", f"checker crashed on this file: {exc}")], None
            all_findings[path] = findings
            if note:
                syntax_notes[path] = note

    print_report(all_findings, files, Path.cwd(), args.verbose, syntax_notes)
    has_errors = any(f.severity == "ERROR" for findings in all_findings.values() for f in findings)
    return 1 if has_errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
