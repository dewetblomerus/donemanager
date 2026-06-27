[
  ## list of tools (see `mix check` docs for a list of default curated tools)
  tools: [
    ## tools we do not run in V1
    {:gettext, false},
    {:dialyzer, false},
    {:doctor, false},

    ## CSP is a deferred hardening step (needs browser testing, no deploy yet)
    {:sobelow, "mix sobelow --exit --ignore Config.CSP"}
  ]
]
