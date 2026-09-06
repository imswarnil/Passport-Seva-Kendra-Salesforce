# force-app

The Passport Seva Kendra SFDX source. Want to deploy this into your own org
and practice against it? See **[../docs/DEPLOY_YOUR_OWN.md](../docs/DEPLOY_YOUR_OWN.md)**.

`manifest/package.xml` is a full-org retrieve manifest (everything the
original build org happens to have installed, including unrelated CRM
Analytics/Wave metadata) — for a clean deploy into a fresh org, use
`manifest/package-psk-core.xml` instead, as the deploy guide above does.
