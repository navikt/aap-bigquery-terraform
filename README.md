# aap-bigquery-terraform

Terraform-konfigurasjon for å strømme data fra Cloud SQL til BigQuery med
[terraform-google-bigquery-datastream](https://github.com/navikt/terraform-google-bigquery-datastream).

## Arkitektur

Dataflyten går fra PostgreSQL i Cloud SQL via Cloud SQL Auth Proxy
og Datastream til BigQuery. Oppsettet bygger på modulen og mønstrene fra
[Flex](https://github.com/navikt/flex-bigquery-terraform) og
[AMT](https://github.com/navikt/amt-bigquery-terraform).

TODO: Dokumenter nettverket og Datastream-konfigurasjonen.

## Miljøer

Hver miljømappe er et selvstendig Terraform-oppsett.

| Mappe | GCP-prosjekt | Region | State-bucket |
|-------|-------------|--------|--------------|
| `dev/` | TODO | TODO | TODO |

## Databaseforutsetninger

Databasebruker, publikasjon og replikeringsslot må finnes før Datastream starter.
Databasebrukeren trenger replikerings- og leserettigheter, og logisk dekoding
må være aktivert på Cloud SQL-instansen.
Modulen oppretter ikke databasebrukeren, publikasjonen eller slotten.
Se [modulens forberedelser](https://github.com/navikt/terraform-google-bigquery-datastream#forberedelser).

En ubrukt replikeringsslot kan holde igjen WAL og fylle databasedisken.
Opprett derfor slotten tett opp mot oppstart av Datastream.

TODO: Dokumenter databasekonfigurasjonen.

## Lokal arbeidsflyt

Installer Terraform-versjonen i [`.terraform-version`](.terraform-version).
Se [HashiCorps installasjonsveiledning](https://developer.hashicorp.com/terraform/install)
for installasjon. Verktøy som `tfenv` kan lese versjonen fra filen.

### Kontrollere konfigurasjonen

Disse kontrollene krever ikke GCP-innlogging. Kjør fra repo-roten:

```sh
terraform version
cd dev
terraform fmt -check -recursive
terraform init -backend=false
terraform validate
```

Hvis formateringskontrollen feiler, kjør `terraform fmt -recursive`
fra `dev/` og se gjennom endringene.

`validate` kontrollerer syntaks og intern sammenheng, ikke tilganger eller
tilkoblinger i GCP. `init -backend=false` er for validering, ikke for
å klargjøre kjøring mot felles state.

### Planlegge og utføre endringer

TODO: Dokumenter innlogging, `init`, `plan` og `apply` mot GCP.

Se gjennom hele planen før `apply`. Avklar uventede slettinger og erstatninger
før du godkjenner.

## GitHub Actions

[Workflowen](.github/workflows/terraform.yml) kjører `fmt`, `init -backend=false`
og `validate` på pull requests og push til `main`. Den kan også startes manuelt
fra Actions-fanen. Den har bare lesetilgang til repoet og ingen GCP-autentisering.

TODO: Konfigurer GCP-autentisering med Workload Identity Federation.

TODO: Legg til `plan` mot dev.

TODO: Konfigurer godkjenning og `apply` av lagret plan.

## Versjoner og state

Oppdater `.terraform-version` og `required_version` i `dev/main.tf` sammen
ved oppgradering. Workflowen leser versjonen fra `.terraform-version`.

Sjekk provider-låsefilen `dev/.terraform.lock.hcl` inn i Git.
Oppgrader providere i egne endringer, og se gjennom låsefilen og nye planer.
Ikke bruk `init -upgrade` i vanlige CI-kjøringer.

TODO: Legg til providere, låsefil og `-lockfile=readonly` i CI.

TODO: Konfigurer GCS-backend.

State og lagrede planer kan inneholde databasepassord og andre sensitive verdier,
selv om Terraform skjuler dem i terminalutskriften. Begrens tilgangen.
Ikke legg state, planfiler eller credentials i Git.

## Manuelt eller eksternt oppsett

TODO: Dokumenter databaseoppsettet.

TODO: Dokumenter manuelt oppsett av state og GCP-tilgang.