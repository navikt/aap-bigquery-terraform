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

### Legge til nye ressurser

Vurder om workflowen trenger flere IAM-rettigheter når du legger til eller
endrer ressurser. Avgrens tilgangen til enkeltressurser der det er mulig.
Oppdater tildelingene i steg 5 og kontrollkommandoene i steg 6 under
[førstegangsoppsett av WIF](#førstegangsoppsett-av-wif-for-github-actions)
i samme endring.

Tildel eventuelle nye rettigheter i GCP før workflowen skal bruke dem.
Kontroller tilgangen med plan og kontrollert apply fra workflowen;
en lokal kjøring bruker dine egne rettigheter.

## GitHub Actions

[Workflowen](.github/workflows/terraform.yml) kjører `fmt`, `init -backend=false -lockfile=readonly` og `validate` på
pull requests og push til `main`. Den kan også startes manuelt fra Actions-fanen.
Valideringsjobben har bare lesetilgang til repoet og ingen GCP-autentisering.

`-backend=false` lar CI validere uten tilgang til state-bucketen.
`-lockfile=readonly` bruker provider-versjonene og kontrollsummene i den
innsjekkede låsefilen uten å endre den.

Jobben `Plan dev` kjører etter validering ved push til `main` og manuell kjøring
fra `main`. Den autentiserer mot GCP med Workload Identity Federation (WIF).
Bare denne jobben har `id-token: write`.
Den kobler til GCS-backenden og kjører `terraform plan`, men ikke `apply`.

### Konfigurasjon

GCP-prosjektet og WIF-providerens fulle ressursnavn er angitt direkte i workflowen.
Se [førstegangsoppsett av WIF](#førstegangsoppsett-av-wif-for-github-actions)
for opprettelse av provider og IAM-binding.

TODO: Konfigurer godkjenning og `apply` av lagret plan.

## Versjoner og state

Oppdater `.terraform-version` og `required_version` i `dev/main.tf` sammen
ved oppgradering. Workflowen leser versjonen fra `.terraform-version`.

Sjekk provider-låsefilen `dev/.terraform.lock.hcl` inn i Git.
Oppgrader providere i egne endringer, og se gjennom låsefilen og nye planer.
Ikke bruk `init -upgrade` i vanlige CI-kjøringer.

### Legge til eller oppgradere providere

Logg inn med `nais login` før du følger stegene under.
De avsluttes med `plan` mot GCP, som i
[den vanlige lokale arbeidsflyten](#planlegge-og-utføre-endringer).

Ved oppgradering, oppdater providerens versjonskrav i `main.tf`.
Kjør deretter fra miljømappen:

```sh
terraform init -upgrade
terraform providers lock \
  -platform=darwin_arm64 \
  -platform=linux_amd64
terraform validate
terraform plan
```

Ved tillegg av en ny provider bruker du `terraform init` uten `-upgrade`,
og følger deretter de samme stegene for kontrollsummer og validering.

`init` oppdaterer låsefilen for valgte provider-versjoner og plattformen du
kjører på. Den sikrer ikke at alle plattformer fra en tidligere provider-versjon
får nye kontrollsummer. `providers lock` registrerer kontrollsummer for både
Mac med Apple Silicon og Linux-runneren i CI. Kjør den ved tillegg og oppgradering
av providere, og legg til flere `-platform`-valg hvis teamet bruker andre plattformer.

Se gjennom versjons- og kontrollsumendringene i `.terraform.lock.hcl` og
ressursendringene i planen før du sjekker inn. CI bruker fortsatt `-lockfile=readonly`.
Se [HashiCorps dokumentasjon om plattformvalg](https://developer.hashicorp.com/terraform/cli/commands/providers/lock#specifying-target-platforms).

### Lagring av state

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
   terraform providers lock \
     -platform=darwin_arm64 \
     -platform=linux_amd64
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

## Førstegangsoppsett av WIF for GitHub Actions

Oppskriften gir GitHub Actions tilgang til å lese og skrive Terraform-state og
administrere bucketen der state lagres.
Den bygger på
[Googles veiledning for konfigurasjon av Workload Identity Federation med GitHub Actions](https://docs.cloud.google.com/iam/docs/workload-identity-federation-with-deployment-pipelines).

Eksempelet bruker dev. For prod eller andre miljøer, sett `PROJECT_ID`,
`PROJECT_NUMBER` og `BUCKET` til miljøets verdier i steg 1.
State-bucketen må finnes fra før. Miljøet trenger også en egen jobb i
[workflowen](.github/workflows/terraform.yml) med riktig GCP-prosjekt,
WIF-provider og Terraform-mappe.
WIF-provideren i steg 3 konfigureres til å godta bare GitHub-kjøringer fra
`main`, utløst av push eller manuell start.

Du trenger `gcloud` og innlogget GitHub CLI (`gh`). Brukeren som utfører oppsettet
trenger rettigheter til å administrere WIF og endre bucketens IAM.
Ved tilgangsfeil, avklar den manglende tillatelsen med prosjektadministrator.

Hvis et API er deaktivert, aktiver det med kommandoen under og prøv steget igjen.
Bruk API-navnet fra feilmeldingen.

```sh
gcloud services enable API_NAVN --project="${PROJECT_ID}"
```

Kjør ett steg om gangen i samme terminal. Kommandoene kan kjøres fra repo-roten.
Ved gjentatt kjøring oppretter du bare ressurser som mangler, og kontrollerer
eksisterende konfigurasjon før du går videre. En mislykket kontroll betyr ikke
at ressursen mangler. IAM-kommandoene i steg 4 og 5 kan gjentas uten å lage
duplikate bindinger; de fjerner heller ikke eksisterende tilganger.

1. Logg inn og sett verdiene for dev. GitHub-ID-ene hentes fra repoets metadata:

   ```sh
   nais login
   PROJECT_ID="aap-dev-e48b"
   PROJECT_NUMBER="617704890496"
   REPOSITORY="navikt/aap-bigquery-terraform"
   BUCKET="aap-terraform-state-dev"
   POOL_ID="github-actions"
   PROVIDER_ID="github-oidc"
   REPOSITORY_ID="$(gh api "repos/${REPOSITORY}" --jq '.id')"
   REPOSITORY_OWNER_ID="$(gh api "repos/${REPOSITORY}" --jq '.owner.id')"
   ```

   Kontroller aktiv `gcloud`-konto, prosjektnummer og GitHub-ID-er:

   ```sh
   gcloud auth list --filter="status:ACTIVE" --format="value(account)"
   gcloud projects describe "${PROJECT_ID}" --format="value(projectNumber)"
   printf 'Repository ID: %s\nOwner ID: %s\n' "${REPOSITORY_ID}" "${REPOSITORY_OWNER_ID}"
   ```

   Prosjektnummeret skal stemme med `PROJECT_NUMBER`, og begge GitHub-ID-ene skal være
   numeriske og ikke tomme. Vi bruker numeriske ID-er i tilgangsreglene fordi
   de ikke kan gjenbrukes dersom et repo- eller organisasjonsnavn blir ledig.

2. Kontroller om poolen allerede finnes:

   ```sh
   gcloud iam workload-identity-pools list \
     --project="${PROJECT_ID}" \
     --location=global
   ```

   Hvis poolen med ID `github-actions` ikke finnes, opprett den:

   ```sh
   gcloud iam workload-identity-pools create "${POOL_ID}" \
     --project="${PROJECT_ID}" \
     --location=global \
     --display-name="GitHub Actions"
   ```

   Hvis poolen finnes, kontroller den:

   ```sh
   gcloud iam workload-identity-pools describe "${POOL_ID}" \
     --project="${PROJECT_ID}" \
     --location=global
   ```

   Gå videre hvis poolen er aktiv og er den tiltenkte poolen for oppsettet.
   Ved ukjent eksisterende bruk, avklar før du fortsetter.

3. Kontroller om OIDC-provideren allerede finnes:

   ```sh
   gcloud iam workload-identity-pools providers list \
     --project="${PROJECT_ID}" \
     --location=global \
     --workload-identity-pool="${POOL_ID}"
   ```

   Hvis provideren med ID `github-oidc` mangler, opprett den med attribute
   mapping og condition:

   ```sh
   gcloud iam workload-identity-pools providers create-oidc "${PROVIDER_ID}" \
     --project="${PROJECT_ID}" \
     --location=global \
     --workload-identity-pool="${POOL_ID}" \
     --display-name="GitHub OIDC" \
     --issuer-uri="https://token.actions.githubusercontent.com" \
     --attribute-mapping="google.subject=assertion.sub,attribute.repository_id=assertion.repository_id" \
     --attribute-condition="assertion.repository_owner_id == '${REPOSITORY_OWNER_ID}' && assertion.repository_id == '${REPOSITORY_ID}' && assertion.ref == 'refs/heads/main' && assertion.event_name in ['push', 'workflow_dispatch']"
   ```

   [`google.subject` er obligatorisk i WIF](https://docs.cloud.google.com/iam/docs/workload-identity-federation#mapping)
   og brukes av GCP til å identifisere innlogget identitet, blant annet i logger.
   Bucket-tilgangen i steg 4 styres av `attribute.repository_id`, ikke subject.
   Condition leser øvrige felt direkte fra tokenet
   via `assertion`, uten ekstra mapping.
   Condition begrenser godkjente tokens til dette repoet i organisasjonen,
   fra `main`, ved push eller manuell kjøring.
   
   Hvis provideren finnes, les konfigurasjonen:
   
   ```sh
   gcloud iam workload-identity-pools providers describe "${PROVIDER_ID}" \
     --project="${PROJECT_ID}" \
     --location=global \
     --workload-identity-pool="${POOL_ID}" \
     --format="yaml(name,state,oidc,attributeMapping,attributeCondition)"
   ```

   Hopp over opprettelsen hvis provideren er aktiv og issuer, mapping og condition
   stemmer med kommandoen over. Avklar eventuelle avvik før du endrer en
   eksisterende provider.


4. Gi GitHub-identiteten tilgang bare til miljøets state-bucket:

   ```sh
   PRINCIPAL="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL_ID}/attribute.repository_id/${REPOSITORY_ID}"

   gcloud storage buckets add-iam-policy-binding "gs://${BUCKET}" \
     --member="${PRINCIPAL}" \
     --role="roles/storage.admin" \
     --condition=None
   ```

   `roles/storage.admin` gir full kontroll over denne bucketen og objektene i den,
   inkludert state og låseobjektet. Rollen dekker også forvaltning av selve
   bucket-ressursen i Terraform. Den gir ikke tilgang til andre buckets.
   For bare backend-bruk ville `roles/storage.objectAdmin` vært tilstrekkelig.
   `--condition=None` legger ingen ekstra betingelser på bucket-tilgangen.
   Kravene til repo, `main` og hendelsestype fra steg 3 gjelder fortsatt.

5. Gi workflowen tilgang til øvrige Terraform-ressurser.

   TODO: Fyll inn nødvendige prosjektroller for Datastream, nettverk og BigQuery
   i `ROLES`. Listen er foreløpig tom, så løkken gjør ingen endringer.

   ```sh
   ROLES=()

   for ROLE in "${ROLES[@]}"; do
     gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
       --member="${PRINCIPAL}" \
       --role="${ROLE}" \
       --condition=None || break
   done
   ```

   Ved nye roller, legg dem til i `ROLES` og kjør løkken på nytt.
   Eksisterende bindinger beholdes uten duplikater. Å fjerne en rolle fra listen
   trekker ikke tilbake tilgangen i GCP.

   Disse rollene gjelder hele prosjektet. Tilgang som skal avgrenses til
   enkeltressurser, gis på den aktuelle ressursen, som for bucketen i steg 4.

6. Kontroller provider og IAM-bindinger:

   ```sh
   gcloud iam workload-identity-pools providers describe "${PROVIDER_ID}" \
     --project="${PROJECT_ID}" \
     --location=global \
     --workload-identity-pool="${POOL_ID}" \
     --format="yaml(name,state,oidc,attributeMapping,attributeCondition)"

   gcloud storage buckets get-iam-policy "gs://${BUCKET}"

   gcloud projects get-iam-policy "${PROJECT_ID}" \
     --flatten="bindings[].members" \
     --filter="bindings.members='${PRINCIPAL}'" \
     --format="yaml(bindings.role,bindings.condition)"
   ```

   Providerens `name` skal være lik `workload_identity_provider` i miljøets
   workflow-jobb. For dev er verdien:

   ```text
   projects/617704890496/locations/global/workloadIdentityPools/github-actions/providers/github-oidc
   ```

   Kontroller at provideren er aktiv, at condition stemmer, og at bucket-policyen
   inneholder riktig principal med `roles/storage.admin`.
   Den siste kommandoen viser prosjektroller gitt direkte til GitHub-identiteten,
   inkludert eventuelle betingelser. Tomt resultat er forventet før slike roller
   er lagt til. Kommandoen viser ikke arvede roller eller bindinger på enkeltressurser.

   Bucket-bindingen kontrolleres med `get-iam-policy` over. Hvis steg 5 utvides
   med bindinger på andre enkeltressurser, legg samtidig til kommandoer her
   som leser IAM-policyen på disse ressursene. Kontroller principal, rolle og
   eventuelle betingelser mot tildelingen i steg 5.

7. Verifiser tilgangen fra GitHub Actions. La WIF- og IAM-endringene få minst
   fem minutter til å tre i kraft. Start workflowen fra
   Actions > Terraform > Run workflow, med `main` valgt.
   Kontroller at autentisering, `terraform init` og planjobben for miljøet
   lykkes. Se gjennom planen og avklar uventede endringer.
   En vellykket plan bekrefter ikke at workflowen kan opprette eller endre ressursene.
   TODO: Verifiser skriverettighetene ved første kontrollerte `apply`.

## Manuelt eller eksternt oppsett

TODO: Dokumenter databaseoppsettet.
