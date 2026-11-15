"""Read and write WoW SavedVariables files: Lua assignments of plain tables.

Only what the game writes is understood: strings, numbers, booleans, nil and
tables with ["key"] or [number] keys (or none, for list items).
"""

import re


class Reader:
    def __init__(self, text):
        self.text = text
        self.at = 0

    def fail(self, message):
        raise ValueError(f"{message} at character {self.at}")

    def skip(self):
        while True:
            match = re.compile(r"(\s+|--\[\[.*?\]\]|--[^\n]*)", re.S).match(self.text, self.at)
            if not match:
                return
            self.at = match.end()

    def peek(self, token):
        self.skip()
        return self.text.startswith(token, self.at)

    def take(self, token):
        if not self.peek(token):
            self.fail(f"expected {token!r}")
        self.at += len(token)

    def string(self):
        self.skip()
        quote = self.text[self.at]
        self.at += 1
        out = []
        while True:
            char = self.text[self.at]
            if char == "\\":
                following = self.text[self.at + 1]
                if following.isdigit():
                    digits = re.match(r"\d{1,3}", self.text[self.at + 1:])[0]
                    out.append(chr(int(digits)))
                    self.at += 1 + len(digits)
                    continue
                out.append({"n": "\n", "t": "\t", "r": "\r"}.get(following, following))
                self.at += 2
                continue
            if char == quote:
                self.at += 1
                return "".join(out)
            out.append(char)
            self.at += 1

    def value(self):
        self.skip()
        if self.peek("{"):
            return self.table()
        if self.text[self.at] in "\"'":
            return self.string()
        match = re.compile(r"-?(?:0x[0-9a-fA-F]+|\d+\.?\d*(?:[eE][-+]?\d+)?|\.\d+)|true|false|nil").match(self.text, self.at)
        if not match:
            self.fail("expected a value")
        self.at = match.end()
        word = match[0]
        if word in ("true", "false"):
            return word == "true"
        if word == "nil":
            return None
        if word.lower().startswith(("0x", "-0x")):
            return int(word, 16)
        number = float(word)
        return int(number) if number.is_integer() and "." not in word and "e" not in word.lower() else number

    def table(self):
        self.take("{")
        result, index = {}, 1
        while not self.peek("}"):
            if self.peek("["):
                self.take("[")
                key = self.value()
                self.take("]")
                self.take("=")
                result[key] = self.value()
            else:
                result[index] = self.value()
                index += 1
            self.skip()
            if self.peek(",") or self.peek(";"):
                self.at += 1
        self.take("}")
        return result


def parse(text):
    """{ name: value } for each top-level assignment."""
    reader, result = Reader(text), {}
    while True:
        reader.skip()
        if reader.at >= len(text):
            return result
        match = re.compile(r"[A-Za-z_][A-Za-z0-9_]*").match(text, reader.at)
        if not match:
            reader.fail("expected a name")
        reader.at = match.end()
        reader.take("=")
        result[match[0]] = reader.value()


def quote(text):
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


def dump_value(value, indent):
    if isinstance(value, bool):
        return "true" if value else "false"
    if value is None:
        return "nil"
    if isinstance(value, (int, float)):
        return repr(value)
    if isinstance(value, str):
        return quote(value)
    lines = ["{"]
    for key, item in value.items():
        key_text = f"[{quote(key)}]" if isinstance(key, str) else f"[{key!r}]"
        lines.append(f"{indent}\t{key_text} = {dump_value(item, indent + chr(9))},")
    lines.append(indent + "}")
    return "\n".join(lines)


def dump(variables):
    return "".join(f"{name} = {dump_value(value, '')}\n" for name, value in variables.items())
