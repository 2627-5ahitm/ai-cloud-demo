# vehicle — Quarkus + Postgres demo on LeoCloud

Source: `~/SynologyDrive/htl/skripten/java.4jg.nvs.sew/presentations/08zh-vehicle-quarkus/2024-05-20.vehicle-demo/vehicle-postgres`
(not copied into this repo). Built inside the DevBox, image pushed to `ghcr.io/htl-leonding/vehicle`.

URL: https://t-stuetz.cloud.htl-leonding.ac.at/ — API `/vehicle`, Swagger UI `/q/swagger-ui/`.

| File | What |
|------|------|
| `postgres.yaml` | PVC `postgres-data` (1Gi), Deployment + Service `postgres` (`postgres:16.4-alpine`) |
| `vehicle.yaml` | Deployment, Service (80 → 8080) and Ingress on `t-stuetz.cloud.htl-leonding.ac.at` |
| `Dockerfile` | JVM image on `eclipse-temurin:21-jre` from a prebuilt `quarkus-app/` |

DB credentials live only in Secret `vehicle-db` (keys `POSTGRES_USER`, `POSTGRES_PASSWORD`,
`POSTGRES_DB`), created once with kubectl — see the header of `postgres.yaml`.

## Rebuild and redeploy

```bash
SRC=~/SynologyDrive/htl/skripten/java.4jg.nvs.sew/presentations/08zh-vehicle-quarkus/2024-05-20.vehicle-demo/vehicle-postgres
TAG=$(date -u +%Y%m%d-%H%M%S)
OUT=$(mktemp -d)

# 1. source into the DevBox
COPYFILE_DISABLE=1 tar --no-xattrs -C "$SRC" --exclude=.DS_Store -cf - pom.xml src http-requests \
  | kubectl exec -i deploy/devbox -- bash -c 'rm -rf /work/projects/vehicle && mkdir -p /work/projects/vehicle && tar -C /work/projects/vehicle -xf -'

# 2. build there (build-time flags: Swagger UI in prod, import.sql in prod)
kubectl exec deploy/devbox -- bash -c 'cd /work/projects/vehicle && mvn -B clean package -DskipTests \
  -Dquarkus.swagger-ui.always-include=true -Dquarkus.hibernate-orm.sql-load-script=import.sql'

# 3. build output out, image built for amd64 and pushed
kubectl exec deploy/devbox -- tar -C /work/projects/vehicle/target -cf - quarkus-app | tar -C "$OUT" -xf -
docker buildx build --platform linux/amd64 -f apps/vehicle/Dockerfile -t ghcr.io/htl-leonding/vehicle:$TAG --push "$OUT"

# 4. bump the image tag in vehicle.yaml, then
kubectl apply -f apps/vehicle/vehicle.yaml && kubectl rollout status deploy/vehicle
```

## Notes

* `-DskipTests`: `VehicleResourceTest.testHelloEndpoint` is the unchanged project-template test and
  expects `Hello RESTEasy` from `/vehicle`. Against the cluster Postgres it fails for that reason only
  (run the build with `QUARKUS_DATASOURCE_JDBC_URL=jdbc:postgresql://postgres:5432/db` plus user and
  password to see it).
* `application.properties` uses `drop-and-create`: every app restart resets the table to the 20
  vehicles from `import.sql`. Data written through the API does not survive a restart.
* Dev Services (Testcontainers) cannot run in the DevBox — no Docker there.
