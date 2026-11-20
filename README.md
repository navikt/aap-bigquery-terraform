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
| `dev/` | `aap-dev-e48b` | `europe-north1` | `aap-terraform-state-dev` |

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
terraform init -backend=false -lockfile=readonly
terraform validate
```

Hvis formateringskontrollen feiler, kjør `terraform fmt -recursive`
fra `dev/` og se gjennom endringene.

`validate` kontrollerer syntaks og intern sammenheng, ikke tilganger eller
tilkoblinger i GCP. `init -backend=false` er for validering, ikke for
å klargjøre kjøring mot felles state.

### Planlegge og utføre endringer

Logg inn:

```sh
nais login
```

Kjør fra `dev/`:

```sh
terraform init -lockfile=readonly
terraform validate
terraform plan
```

`init` kobler opp GCS-backenden. Prosjektet for ressursene er angitt i
provider-konfigurasjonen i `main.tf`, uavhengig av standardprosjektet i `gcloud`.

Se gjennom hele planen før `apply`. Avklar uventede slettinger og erstatninger
før du godkjenner.

For avtalt lokal kjøring:

```sh
terraform apply
```

Kommandoen lager en ny plan og ber om godkjenning. Den utfører ikke automatisk
planen fra forrige `terraform plan`.

## GitHub Actions

[Workflowen](.github/workflows/terraform.yml) kjører `fmt`, `init -backend=false -lockfile=readonly` og `validate` på
pull requests og push til `main`. Den kan også startes manuelt fra Actions-fanen. Den har bare lesetilgang til repoet
og ingen GCP-autentisering.

`-backend=false` lar CI validere uten tilgang til state-bucketen.
`-lockfile=readonly` bruker provider-versjonene og kontrollsummene i den
innsjekkede låsefilen uten å endre den. Kontrollene kjører ikke `plan` eller `apply`.

TODO: Konfigurer GCP-autentisering med Workload Identity Federation.

TODO: Legg til `plan` mot dev.

TODO: Konfigurer godkjenning og `apply` av lagret plan.

## Versjoner og state

Oppdater `.terraform-version` og `required_version` i `dev/main.tf` sammen
ved oppgradering. Workflowen leser versjonen fra `.terraform-version`.

Sjekk provider-låsefilen `dev/.terraform.lock.hcl` inn i Git.
Oppgrader providere i egne endringer, og se gjennom låsefilen og nye planer.
Ikke bruk `init -upgrade` i vanlige CI-kjøringer.

State lagres i GCS-bucketen angitt i `dev/backend.tf`.
Bucketen forvaltes av `google_storage_bucket.terraform_state` i `dev/main.tf`.
Versjonering er aktivert, uniform bucket-level access er på og offentlig tilgang
er blokkert. `force_destroy = false` hindrer Terraform i å slette bucketen
mens den inneholder objekter.

State og lagrede planer kan inneholde databasepassord og andre sensitive verdier,
selv om Terraform skjuler dem i terminalutskriften. Begrens tilgangen.
Ikke legg state, planfiler eller credentials i Git.

## Førstegangsoppsett av state

State-bucketen må finnes før Terraform kan bruke GCS-backend.
Følgende engangsprosedyre ble brukt for dev 20. november 2026,
med utgangspunkt i [Googles veiledning](https://docs.cloud.google.com/docs/terraform/resource-management/store-state).
Bucketen ble opprettet med Terraform, ikke manuelt i GCP.

For et nytt miljø, for eksempel prod, bruk en egen mappe (`prod/`),
provider-konfigurasjon for riktig GCP-prosjekt og et eget, globalt unikt bucket-navn.
Følg stegene under i den nye mappen, med egen state for miljøet.

For et eksisterende miljø bruker du [den vanlige lokale arbeidsflyten](#planlegge-og-utføre-endringer).

1. Opprett `main.tf` i den nye miljømappen med Terraform-versjon, Google-provider
   og bare state-bucketen. Bruk `dev/main.tf` som eksempel, men tilpass prosjekt,
   bucket-navn og lokasjon til det nye miljøet. Vent med `backend.tf` og øvrige ressurser.
2. Logg inn med `nais login`. Bruk eksisterende rettigheter først.
   Ved tilgangsfeil, stopp og avklar den manglende tillatelsen før du fortsetter.
3. Gå til miljømappen fra repo-roten, for eksempel `cd prod`.
   Kjør deretter én kommando om gangen:

   ```sh
   terraform fmt
   terraform init
   terraform validate
   terraform plan
   terraform apply
   ```

   Planen skal bare opprette bucket-ressursen. Kontroller prosjekt i
   provider-konfigurasjonen og navn, lokasjon, versjonering og tilgangsinnstillinger
   i planen før godkjenning. State lagres lokalt i dette steget.
4. Legg til `backend.tf` i samme miljømappe. For dev er innholdet:

   ```hcl
   terraform {
     backend "gcs" {
       bucket = "aap-terraform-state-dev"
     }
   }
   ```

   Bruk riktig bucket-navn ved oppsett av et annet miljø.
5. Migrer lokal state til bucketen:

   ```sh
   terraform init -migrate-state
   ```

   Godkjenn kopiering av eksisterende state når Terraform spør.
6. Kontroller at bucket-ressursen finnes i state, og at planen viser ingen endringer:

   ```sh
   terraform state list
   terraform plan
   ```

7. Når migreringen er bekreftet og planen viser ingen endringer, slett
   `terraform.tfstate` og `terraform.tfstate.backup` i miljømappen hvis de finnes.

Behold `.terraform/`, som inneholder lokal backend-konfigurasjon og nedlastede providere.
Sjekk inn konfigurasjonen og `.terraform.lock.hcl`, men ikke state-filene.

## Manuelt eller eksternt oppsett

TODO: Dokumenter databaseoppsettet.

TODO: Dokumenter GCP-tilgang for GitHub Actions.