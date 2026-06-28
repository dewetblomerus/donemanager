# Local test scripts

Ad-hoc scripts for poking the running app by hand. Not the Elixir test suite —
that lives in `app/test`.

## scan_tag.sh

Simulates an NFC tag scan (`POST /v1/tags/{external_id}/scans`) with an
`access_token` body parameter.

1. Start the app: `cd app && mix phx.server`
2. Mint a token in `iex -S mix` (owner scope required):

   ```elixir
   scope = DoneManager.Households |> ... # an owner's %Scope{}
   {:ok, _token, plaintext} = DoneManager.Integrations.create_token(scope)
   plaintext  # copy this
   ```

3. Put the plaintext token in `test/.envrc.secrets`:

   ```bash
   export DM_ACCESS_TOKEN=<plaintext>
   ```

4. Allow direnv from `test/` so `DM_ACCESS_TOKEN` is exported into your shell:

   ```bash
   cd test
   direnv allow
   ```

5. Scan:

   ```bash
   # Fresh tag (registers it, then assign it to a task in the web UI):
   ./scan_tag.sh

   # Re-scan a known tag (e.g. one assigned to a task -> completes it):
   ./scan_tag.sh 0190c0de-1234-7abc-8def-0123456789ab
   ```

Override the host with `DM_BASE_URL` (default `http://localhost:4000`).
