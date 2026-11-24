#!/usr/bin/env python3
"""Runs every case through Docker Compose and writes the results as a Swift fixture
(Tests/ComposeCommandClaimKitTests/ParityFixture.swift).

A case is one service, `web`, with a `command:` and/or `entrypoint:` written as YAML text, an image built from a
Dockerfile (`FROM scratch`, so its ENTRYPOINT and CMD are all there is), an optional `.env`, shell variables, and an
optional `docker compose run` line. Expected: whether `docker compose config` refuses the file ("invalid command line
string"), and otherwise the container's Path and Args from `docker compose create` (or `docker compose run -d`) and
`docker inspect`, or the daemon's "no command specified". The kit must give the same words for every case.

Needs Docker Compose with a running daemon; run from the package root: python3 Scripts/parity.py [count]"""
import json
import os
import random
import shlex
import subprocess
import sys
import tempfile

DOCKERFILES = [
    "FROM scratch\nLABEL kit=none\n",
    "FROM scratch\nCMD [\"node\", \"server.js\"]\n",
    "FROM scratch\nENTRYPOINT [\"/entry.sh\"]\nCMD [\"serve\"]\n",
    "FROM scratch\nENTRYPOINT exec /run --flag\n",
    "FROM scratch\nCMD npm start\n",
    "FROM scratch\nENTRYPOINT [\"python\", \"manage.py\"]\nCMD [\"runserver\"]\n",
]

# Values as YAML text after `command: ` (None: the key is left out). Block scalars carry their own lines.
COMMANDS = [
    None, "npm run dev", "cd /app && npm start", "\"echo $HOME && ls -l > out.txt\"", "\"echo $$HOME\"",
    "worker --queue fast", "[\"npm run dev\"]", "[\"npm\", \"run\", \"dev\"]", "[]", "\"\"", "null",
    "\"sh -c 'echo $$HOME && ls'\"", "echo $GREETING", "\"echo ${GREETING:-hello world}\"",
    "\"echo \\\"${GREETING:-hello world}\\\"\"", "'echo \"a b\" c\\ d'", "echo a; echo b", "\"echo a | wc -l\"",
    "\"echo a 2>&1\"", "\"echo $(date) x\"", "echo 'a && b' x", "FOO=bar npm start", "\"npm start &\"",
    "echo ~ *.txt", "\"python -c \\\"print(1)\\\"\"", "echo (a)", "\"echo 'unclosed\"", "echo a\\",
    "[\"sh\", \"-c\", \"cd /app && npm start\"]", "[\"echo\", \"$$GREETING\"]", "[\"echo\", \"$GREETING\"]",
    "echo $TAG", "\"echo ${TAG:-latest} ${TAG:+set}\"", "x y", "migrate --all", "\"echo #not-a-comment\"",
    "echo x # a comment", ">\n      sh -c \"npm install\n      && npm start\"", "|\n      npm install\n      npm start",
    "\n    - sh\n    - -c\n    - |\n      npm install\n      npm start", "\n    - python\n    - app.py",
    "\"echo x2>f\"", "\"echo 2x>f\"", "\"echo \\\"\\\"&&x\"", "\"echo $${A} $$A\"", "\"echo a\\\\tb\"",
    "'echo \"e\\nf\"'", "\"echo `a;b` c\"", "\"echo $$(a;b) c\"",
]

ENTRYPOINTS = [
    None, None, None, "/bin/sh -c", "[\"sh\", \"-c\"]", "\"\"", "[]", "[\"/sbin/tini\", \"--\"]", "/app/start.sh",
    "\"/bin/sh -c 'echo $$0 $$1'\"", "[\"npm run dev\"]", "\"sh -c\"",
]

ENVS = ["", "GREETING=hi\n", "GREETING=\"hi there\"\nTAG=1.2\n", "TAG=\n"]
SHELLS = [{}, {"TAG": "9.9"}, {"GREETING": "from shell"}]
# (options before the service, arguments after it)
RUNS = [None, None, None, ([], ["npm", "test"]), (["--entrypoint", "/bin/sh"], ["-c", "ls"]),
        (["--entrypoint", "/bin/sh"], []), (["--entrypoint="], []), ([], ["migrate", "--all"]),
        (["--entrypoint", "/bin/sh -c"], ["echo hi"]), ([], ["a b"]), ([], [])]

HOME = "/Users/x"
BASE_ENV = {"PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin", "HOME": HOME,
            "DOCKER_CONFIG": os.path.expanduser("~/.docker"),
            "DOCKER_HOST": "unix://" + os.path.expanduser("~/.colima/default/docker.sock")}


def swift(text):
    return "\"" + text.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n").replace("\t", "\\t") + "\""


def compose_text(image_tag, command, entrypoint, oracle):
    lines = ["services:", "  web:"]
    lines.append("    image: " + image_tag if oracle else "    build: .")
    if oracle:
        lines.append("    pull_policy: never")
    for key, value in (("entrypoint", entrypoint), ("command", command)):
        if value is None:
            continue
        if value.startswith("\n"):
            lines.append("    %s:%s" % (key, value))
        else:
            lines.append("    %s: %s" % (key, value))
    return "\n".join(lines) + "\n"


def build_images():
    tags = []
    with tempfile.TemporaryDirectory(dir="/tmp") as context:
        for index, text in enumerate(DOCKERFILES):
            tag = "cckp-image-%d" % index
            subprocess.run(["docker", "build", "-q", "-t", tag, "-f", "-", context], input=text, text=True,
                           capture_output=True, check=True, env=dict(os.environ, DOCKER_BUILDKIT="0"))
            tags.append(tag)
    return tags


def inspect(name):
    out = subprocess.run(["docker", "inspect", "--format", "{{json .Path}}\t{{json .Args}}", name],
                         capture_output=True, text=True)
    if out.returncode != 0:
        return None
    path, args = out.stdout.strip().split("\t")
    return [json.loads(path)] + json.loads(args)


def oracle(case, tags, index):
    project = "cckp%d" % index
    with tempfile.TemporaryDirectory(dir="/tmp") as root:
        with open(os.path.join(root, "compose.yaml"), "w") as handle:
            handle.write(compose_text(tags[case["image"]], case["command"], case["entrypoint"], True))
        if case["dotEnv"]:
            with open(os.path.join(root, ".env"), "w") as handle:
                handle.write(case["dotEnv"])
        env = dict(BASE_ENV, **case["shell"])
        base = ["docker", "compose", "-p", project, "--project-directory", root, "-f",
                os.path.join(root, "compose.yaml")]
        config = subprocess.run(base + ["config", "--format", "json"], capture_output=True, text=True, env=env)
        if config.returncode != 0:
            if "invalid command line string" in config.stderr:
                return {"refused": True}
            return {"skip": config.stderr.strip().splitlines()[-1]}
        try:
            if case["run"] is None:
                made = subprocess.run(base + ["create"], capture_output=True, text=True, env=env)
                if "no command specified" in made.stderr:
                    return {"noCommand": True}
                return {"words": inspect(project + "-web-1")}
            name = project + "-run"
            options, arguments = case["run"][0]
            made = subprocess.run(base + ["run", "-d", "--no-deps", "--name", name] + options + ["web"] + arguments,
                                  capture_output=True, text=True, env=env)
            if "no command specified" in made.stderr:
                return {"noCommand": True}
            return {"words": inspect(name)}
        finally:
            subprocess.run(base + ["down", "--remove-orphans"], capture_output=True, env=env)
            subprocess.run(["docker", "rm", "-f", project + "-run"], capture_output=True)


def cases(count):
    generator = random.Random(1124)
    made = []
    for command in COMMANDS:
        made.append({"image": 1, "command": command, "entrypoint": None, "dotEnv": "", "shell": {}, "run": None})
    for entrypoint in ENTRYPOINTS:
        for image in range(len(DOCKERFILES)):
            made.append({"image": image, "command": None, "entrypoint": entrypoint, "dotEnv": "", "shell": {},
                         "run": None})
    while len(made) < count:
        run = generator.choice(RUNS)
        made.append({"image": generator.randrange(len(DOCKERFILES)), "command": generator.choice(COMMANDS),
                     "entrypoint": generator.choice(ENTRYPOINTS), "dotEnv": generator.choice(ENVS),
                     "shell": generator.choice(SHELLS),
                     "run": None if run is None else (run, " ".join(
                         ["docker compose run --rm"] + [shlex.quote(word) for word in run[0]] + ["web"]
                         + [shlex.quote(word) for word in run[1]]))})
    return made


def main():
    count = int(sys.argv[1]) if len(sys.argv) > 1 else 260
    tags = build_images()
    rows = []
    skipped = 0
    for index, case in enumerate(cases(count)):
        result = oracle(case, tags, index)
        if "skip" in result or result.get("words") is None and not result.get("refused") and not result.get("noCommand"):
            skipped += 1
            print("skip %d: %s" % (index, result.get("skip", "no container")), file=sys.stderr)
            continue
        shell = dict(case["shell"], HOME=HOME)
        expected = "nil" if result.get("refused") else "[]" if result.get("noCommand") else \
            "[" + ", ".join(swift(word) for word in result["words"]) + "]"
        rows.append("    ParityCase(compose: %s,\n               dockerfile: %s, dotEnv: %s,\n"
                    "               shell: [%s], run: %s,\n               expected: %s)" % (
                        swift(compose_text("", case["command"], case["entrypoint"], False)),
                        swift(DOCKERFILES[case["image"]]), swift(case["dotEnv"]),
                        ", ".join("%s: %s" % (swift(k), swift(v)) for k, v in sorted(shell.items())) or ":",
                        "nil" if case["run"] is None else swift(case["run"][1]), expected))
    version = subprocess.run(["docker", "compose", "version", "--short"], capture_output=True, text=True).stdout.strip()
    with open("Tests/ComposeCommandClaimKitTests/ParityFixture.swift", "w") as handle:
        handle.write("// Generated by Scripts/parity.py against Docker Compose %s. Do not edit by hand.\n" % version)
        handle.write("// swiftlint:disable all\n\n")
        handle.write("/// One service, `web`, run through `docker compose config`, `create` (or `run -d`) and `docker inspect`.\n")
        handle.write("/// `expected` is the container's Path and Args; `[]` is \"no command specified\"; `nil` is a file\n")
        handle.write("/// `docker compose` refuses.\n")
        handle.write("struct ParityCase: Sendable {\n    let compose: String\n    let dockerfile: String\n")
        handle.write("    let dotEnv: String\n    let shell: [String: String]\n    let run: String?\n")
        handle.write("    let expected: [String]?\n}\n\n")
        handle.write("let parityCases: [ParityCase] = [\n" + ",\n".join(rows) + "\n]\n")
    print("%d cases written, %d skipped" % (len(rows), skipped))
    for tag in tags:
        subprocess.run(["docker", "rmi", "-f", tag], capture_output=True)


if __name__ == "__main__":
    main()
