# Serve the Web Prompt from the Broker through Tailscale Serve

When Key Kong runs on a machine the user reaches remotely, the Broker itself
serves the Web Prompt instead of handing the Request to another web
application. For the duration of one Request, the Broker listens on a loopback
port recorded by `keykong prompt web`, and Tailscale Serve exposes that port at
the node's HTTPS URL under `/keykong`. The listener closes when the Request is
submitted, cancelled, or expires, so this adds no daemon and keeps the one-shot
boundary from ADR 0001.

Each Request has an unguessable page URL. The stable `/keykong` URL redirects to
the waiting Request so callers can direct the user to it before the blocking
invocation. Requests that find the port busy wait for it, so Web Prompt
Requests on one machine are presented one at a time.

Between Requests nothing listens on the port, so a local program that binds it
would receive `/keykong` traffic without the login check. `keykong prompt web`
picks the port below the ephemeral ranges, so programs that let the system
choose a port cannot take it, and rerunning the command moves to a new port.
Keeping the port bound would need a daemon, mounting per Request would leave
the mount behind whenever the deadline or a crash cuts cleanup short, and
Tailscale accepts Unix socket targets only from root.

The Web Prompt accepts only requests carrying the configured
`Tailscale-User-Login`, which Tailscale Serve sets for tailnet clients, and
same-origin form submissions. Local processes can reach the loopback port
directly and set that header themselves; like other local software, they are
outside the threat model.

This was chosen over hosting Requests in a registered web application such as
Monke See. That design needed host registration, credentials, a versioned
exchange protocol, and placed submitted secrets inside a much larger
application, only to obtain a URL that Tailscale Serve provides directly.
