# The Switchover agent logic and the GSLB

There are three different DNS records the GSLB can direct traffic to depending on the results of their health checks and the GSLB's health.  These are:

    - Gold IP Address
    - Gold DR IP Address
    - No resolved IP address.

## Logic behind which IP address is resolved:

0.) If the GSLB is broken or down, no Resolved IP address.  The switchover agent sees this as an 'error'

1.) If the gold health check passes, the GSLB returns the gold IP address.  The switchover agent sees this as the 'active IP address'

2.) If the gold health check fails and GoldDR's passes, the GSLB returns the GoldDR IP address.  The switchover agent sees this as the 'passive IP address'

3.) If the gold health check fails and GoldDR's fails, no Resolved IP address.  The switchover agent sees this as an 'error'

## Logic behind what alerts and actions are triggered by the switchover agent.

The switchover agent only evalutes changes in the returned IP address.  To determine whether or not failover needs to be triggered, or alerts fired off. The logic depends on the current resoloved IP (active, passive, error) and the previous valid IP (active, passive, undefined)

|   |        ||  Gold(active) | GoldDR(passive)  | 'undefined'  |
|---|---     |---|---|---|---|
|   | Gold(active)   || Internal Alert <br /> Gold Restored  | Alert Clients <br />Gold Restored <br /> CSS Active  | Internal Alert <br /> agent restart  |
|   | GoldDR(passive) || Failover Triggered  <br /> Alert clients <br /> of DR status <br /> CSS Maintenance |  Internal Alert <br /> GoldDR restored  | Internal Alert <br /> agent restart  |
|   | Error  || Internal Alert <br />Gold Down  | Internal Alert <br />GoldDR Down  | Internal Alert <br /> agent restart  |

None of the internal alerts are created yet.  The tests will need to be updated when they are.
