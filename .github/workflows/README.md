# GitHub Workflows

This directory houses our CI/CD code for both AWS Elastic Container Registry (ECR) and GitHub Container Registry (ghcr.io) using GitHub Actions. GitHub Actions as a tool provides an automated end to end deployment stream which couples continues integration with continues deployment eliminating human error in the process.

## deploy-ecs.yml (Alternatively: deploy-ecs.yml.disabled)

You might see this file as either deploy-ecs.yml or deploy-ecs.yml.disabled: When it is `deploy-ecs.yml.disabled` GitHub Actions will ignore this file. When it is `deploy-ecs.yml` GitHub Actions reads this file and executes the code pushing it to ECR.

The V1 images consists of a Next.js frontend and a Flask backend. These are original images from the course with a few modifications for security and production.
This workflow focuses on deploying both to AWS ECR. Note, the ECR registry must already exist before we can push to it, otherwise the build will fail. The instructions for deploying to ECR are in [03-aws-ecr_link_to_path_(href?alternative)].

The workflow is split into three jobs:

1. Detect change
   - This runs first. It scans the commits looking for change. If change is found then it flags it.
2. build-v1-frontend
   - This only runs if change is detected on the source code `apps/v1-frontend-nextjs`
   - Builds the docker image on GitHub then logs into ECR using IAM role and pushes the image to `rr-dev-frontend` repository.
3. build-v1-backend
   - This only runs if change is detected on the source code `apps/v1-backend-flask`
   - Builds the docker image on GitHub then logs into ECR using IAM role and pushes the image to `rr-dev-backend` repository.

The jobs comprise of steps which are the tasks/actions to be performed against some resource. This could be running a shell command:

```
      - name: Build and Push Frontend
        env:
          ECR_REGISTRY: ${{ steps.login-ecr.outputs.registry }}
          ECR_REPOSITORY: rr-dev-frontend
          IMAGE_TAG: ${{ github.sha }}
        working-directory: ./apps/v1-frontend-nextjs
        run: |
          docker build -t $ECR_REGISTRY/$ECR_REPOSITORY:latest -t $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG .
          docker push $ECR_REGISTRY/$ECR_REPOSITORY --all-tags
```

Above, this step belongs to the `build-v1-frontend` job. It does the following:

1. Builds an image and tags using environment variables which are linked with corresponding ECR credentials
   - Note, the `IMAGE_TAG` is the `{{github.sha}}` value, this will be useful later
2. Pushes the image just created to the ECR registry

For the job to actually run, it needs to be triggered. Here we've used two types of triggers:

```
on:
  push:
    branches: [ "main" ]
    paths:
      - 'apps/v1-frontend-nextjs/**'
      - 'apps/v1-backend-flask/**'
  workflow_dispatch:
```

Above the two triggers are defined, usually at the top of the file:

1. On push
   - If we push to any of the specified paths, this triggers a build
2. On Workflow dispatch
   - We can trigger a rebuild online, on the GitHub UI workflow dispatch (see the image below)

[image_of_workflow_deployment(href?alternative)]

## deploy-ghcr-k8s.yml

This is the upgrade to `deploy-ecs.yml`, it's a CI/CD pipeline designed for Kubernetes (K8s) and Istio-based infrastructure deployment.
As usual the build can be triggered on push or by workflow dispatch given detection of a change in the source code.

```
concurrency:
  group: update-manifests
  cancel-in-progress: false
```

Concurrency lock ensures that only one workflow can push changes up to completion. Once complete, the lock is removed and other changes can be pushed.
Thus it guarantees that every single commit that triggers the pipeline gets fully built, fully pushed, and successfully committed back to Git sequentially.

Here we deploy/push the following images to ghcr.io:

1. V1 Next.js frontend
2. V1 Flask backend
3. V2 Vite frontend
4. V2 Go backend

To build these images, GitHub spins up a container usually an Ubuntu container to run docker build. Note, these are four independent builds and they run in parallel, next to each other, not in sequence.

Every build job undertakes the following tasks:

1. Logs into GHCR using the automatic workflow `${{ secrets.GITHUB_TOKEN }}`

2. Builds the Docker image.

3. Lowercases the image name (to comply with GHCR naming rules).

4. Tags the image with `:latest` and the unique commit SHA `(${{ github.sha }})`

5. Pushes all tags to GHCR.

If the build runs successfully, then the build must write the new SHA-1 value back into the Kubernetes manifest, yaml file. This is done to facilitate Kubernetes deployment rollback i.e. tagging the images with `:latest` then when we rollback, the previous image will also have the same tag `:latest`, making the images indistinguishable from one another. Essentially Kubernetes will not have the means to identify one image from another.

```
IMAGE_TAG: ${{ github.sha }}
```

However, tagging the image with the SHA-1 will give each image a unique identifier that can be rolled back to with ease.

```
    steps:
      - uses: actions/checkout@v4
        with:
          ref: ${{ github.ref }}
      - name: Install yq
        uses: mikefarah/yq@v4                   <---------WHAT IS THIS????
      - name: Pin changed apps to the new SHA
        run: |
          set -euo pipefail
          OWNER=$(echo "${{ github.repository_owner }}" | tr '[:upper:]' '[:lower:]')
          REG="ghcr.io/${OWNER}"
          pin() {
            local file="$1" repo="$2"
            if [ -f "$file" ]; then
              yq -i ".spec.template.spec.containers[0].image = \"${REG}/${repo}:${IMAGE_TAG}\"" "$file"
              echo "Pinned $file -> ${REG}/${repo}:${IMAGE_TAG}"
            else
              echo "Skip (manifest absent): $file"
            fi
          }
          if [ "${{ needs.detect-changes.outputs.v1_frontend }}" = "true" ]; then
            pin "${MANIFEST_DIR}/v1-frontend-nextjs-deployment.yml" "rr-v1-frontend"
          fi
          if [ "${{ needs.detect-changes.outputs.v1_backend }}" = "true" ]; then
            pin "${MANIFEST_DIR}/v1-backend-flask-deployment.yml" "rr-v1-backend"
          fi
          if [ "${{ needs.detect-changes.outputs.v2_frontend }}" = "true" ]; then
            pin "${CANARY_MANIFEST_DIR}/v2-frontend-vite-deployment.yml" "rr-v2-frontend"
          fi
          if [ "${{ needs.detect-changes.outputs.v2_backend }}" = "true" ]; then
            pin "${CANARY_MANIFEST_DIR}/v2-backend-go-deployment.yml" "rr-v2-backend"
          fi
```

This process requires:

1. Install `yq:` A command-line YAML processor.

2. Updates YAML Deployments: Dynamically rewrites the .spec.template.spec.containers[0].image value with the new commit SHA tag in the corresponding deployment files:
   - V1 Apps (Stable Dev Track) live in: infrastructure/05-aws-k8s/k8s-manifests/dev-apps/deployments/

   - V2 Apps (Canary Track) live in: infrastructure/05-aws-k8s/k8s-manifests/canary-staging/

3. Commits & Pushes Back: Commits the updated YAML manifest files directly back to `main` as github-actions[bot].

The Kubernetes cluster monitors ghcr.io using ArgoCD for any change, every 3 minutes, and pulls and deploys any change found accordingly.

## Conclusion

The GitHub Actions workflow files splits the push to ECR and ghcr.io exclusively into two files. Instead of carrying out the docker build locally, the docker build task is carried out by Github, remotely, in the background. The actual execution is triggered in one of two ways, on push or workflow dispatch on GitHub Actions. Further, new builds are only triggered if a change occurs in the source files. No change, no build. The decoupled nature of the build, means that the jobs run in parallel, this is a highly efficient CI/CD approach to deployment.

Tagging the image with the `github.sha` value give it a unique identifier which enables Kubernetes deployment rollbacks to a previous exact image, with ease.
Without it, Kubernetes would not be able to distinguish the current image from the previous image, they would all look the same.
