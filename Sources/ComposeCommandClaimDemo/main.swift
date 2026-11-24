import ComposeCommandClaimKit

/// Ten answers a model might give about what compose services run, checked against compose's own reading of the
/// files they show. Every expectation printed here was probed with `docker compose config` and
/// `docker compose create` + `docker inspect` (Docker Compose 2.32.4).

let fence = "```"

func show(_ title: String, _ report: CommandReport) {
    print("== \(title)")
    print("   verdict: \(report.verdict.rawValue) (\(report.summary))")
    for finding in report.findings {
        let mark = switch finding.severity {
        case .holds: "holds    "
        case .unchecked: "unchecked"
        case .caution: "caution  "
        case .wrong: "WRONG    "
        }
        let slip = finding.slip.map { " [\($0.rawValue)]" } ?? ""
        print("   \(mark) \(finding.claim.sentence)\(slip)")
        if finding.severity >= .caution { print("             -> \(finding.explanation)") }
        if case let .unchecked(reason) = finding.outcome { print("             -> \(reason)") }
    }
}

let checker = CommandClaimChecker()

let chained = """
Here is the service:

\(fence)yaml
services:
  web:
    build: .
    command: cd /app && npm start
\(fence)

Compose runs `command` through a shell, so `web` runs `cd /app && npm start`.
"""
show("1. a chained command (compose stops at &&)", checker.check(chained))

let fixed = """
\(fence)yaml
services:
  web:
    build: .
    command: ["sh", "-c", "cd /app && npm start"]
\(fence)

Compose does not run a `command` string through a shell, so the list starts one: `web` runs `cd /app && npm start`.
"""
show("2. the fix: a shell started on purpose", checker.check(fixed))

let guide = """
In `docker-compose.yml`, a string `command` is split into words without a shell, so `&&` is passed to the program \
as a literal argument.
"""
show("3. a guide's explanation of the same bug", checker.check(guide))

let environment = """
\(fence)yaml
services:
  greeter:
    image: alpine:3.20
    environment:
      GREETING: hello
    command: echo $GREETING
\(fence)

`$GREETING` becomes `hello`, because compose expands variables in `command` from the `environment:` block.
"""
show("4. a variable set only in environment:", checker.check(environment))

let tini = """
\(fence)dockerfile
FROM node:20-alpine
ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["node", "server.js"]
\(fence)

\(fence)yaml
services:
  app:
    build: .
    entrypoint: ["/sbin/tini", "--"]
\(fence)

Setting `entrypoint` keeps the image's `CMD`, so `app` runs `/sbin/tini -- node server.js`.
"""
show("5. adding tini through entrypoint:", checker.check(tini))

let run = """
\(fence)yaml
services:
  web:
    build: .
    command: npm run dev
\(fence)

`docker compose run --rm web npm test` runs `npm test`: the arguments after the service replace its `command`.
With `docker compose run --rm web npm test`, the container runs `npm run dev npm test`.
"""
show("6. docker compose run, right and wrong", checker.check(run))

let split = """
\(fence)yaml
services:
  worker:
    image: alpine:3.20
    entrypoint: ["sh", "-c"]
    command: echo ready
\(fence)

`worker` runs `echo ready` through `sh -c`.
"""
show("7. sh -c handed its script in pieces", checker.check(split))

let kubernetes = """
\(fence)yaml
apiVersion: v1
kind: Pod
spec:
  containers:
    - name: web
      image: node:20
      command: ["npm"]
      args: ["start"]
\(fence)

Here `command` replaces the image's `ENTRYPOINT`.
"""
show("8. a Kubernetes manifest (left alone)", checker.check(kubernetes, context: "how do I run this with compose?"))

let quiet = """
\(fence)yaml
services:
  api:
    image: python:3.12-slim
    command: python -m http.server 8000
\(fence)

`api` runs `python -m http.server 8000`. Compose fills `$VAR` in `command` from your shell or `.env` when it reads \
the file, and an empty `command: []` falls back to the image's CMD.
"""
show("9. a correct answer stays quiet", checker.check(quiet))

let ledger = CommandLedger()
let first = await ledger.review("""
\(fence)yaml
services:
  web:
    image: node:20
    command: npm run dev
\(fence)
""")
show("10a. a conversation: the file", first)
let second = await ledger.review("""
The arguments after `docker compose run` are appended to the service's command.
""", context: "Does `docker compose run web npm test` keep `npm run dev`?")
show("10b. a later turn without the file", second)
let third = await ledger.review("""
Yes: `docker compose run` arguments are appended to the service's command.
""")
show("10c. the same mistake again", third)
let statistics = await ledger.statistics
print("== ledger: \(statistics.reviews) reviews, \(statistics.claims) claims, \(statistics.flagged) flagged, "
    + "\(statistics.repeated) repeated")
