# Edge Network Egress

The data guard endpoint model classifies destinations before simulated forwarding or audit/report persistence. Classification is local and deterministic; normal tests do not make external network calls.

Aegis Edge remains simulation/SITL/customer-evaluation software. It is not real-flight readiness, certification, detect-and-avoid, or autopilot replacement evidence.

Endpoint kinds include `localhost`, `private_network`, `ground_control_station`, `px4_sitl`, `ardupilot_sitl`, `fake_adapter`, `customer_endpoint`, `cloud_endpoint`, `webhook`, `tunnel_service`, `paste_site`, `direct_ip`, and `unknown`.

Security rules:

- Unknown endpoints are not safe by default.
- Direct public IP destinations are not safe by default.
- Webhook, request-bin, paste, and tunnel destinations are suspicious by default.
- Localhost and private network endpoints require explicit policy in strict flows unless using scoped fake/SITL defaults.
- Simulated customer endpoints require explicit policy and should be labeled `customer_endpoint`.
- URLs are redacted before persistence. Paths are minimized, query strings are bounded, and secret-like query values are replaced with redaction markers.

Use `aegis-edge network explain --policy <policy> --endpoint <endpoint.json>` to inspect the endpoint classification and the matching policy decision without sending network traffic.
