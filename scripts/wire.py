"""Quest Party's wire format (QuestParty/comms/protocol.lua), for scripts:
"1:E:key=value;key=#12", where #12 is a number."""


def decode(text):
    """Returns (version, kind, fields) for one message."""
    version, kind, body = text.split(":", 2)
    fields = {}
    for pair in body.split(";"):
        if "=" in pair:
            key, value = pair.split("=", 1)
            fields[key] = int(value[1:]) if value.startswith("#") and value[1:].lstrip("-").isdigit() else value
    return version, kind, fields


def encode(version, kind, fields):
    def text(value):
        return f"#{value}" if isinstance(value, int) else str(value)
    return f"{version}:{kind}:" + ";".join(f"{key}={text(fields[key])}" for key in sorted(fields))
