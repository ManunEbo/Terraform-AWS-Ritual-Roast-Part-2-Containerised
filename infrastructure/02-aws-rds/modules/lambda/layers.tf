#------------------------------------------------------------
#         Ritual Roast: Automated Layer Packaging
#------------------------------------------------------------

resource "null_resource" "rr_build_and_clean_layer" {
  triggers = {
    # Increment this version string to force a manual rebuild of the layer
    dependency_version = "pymysql-v1.1"
  }

  provisioner "local-exec" {
    command = <<EOT
        set -e
        # 1. Clean up any previous builds
        rm -rf ${path.module}/layers/python
        rm -f ${path.module}/layers/db_driver.zip
        
        mkdir -p ${path.module}/layers/python

        # 2. Install purely from source, ignore caches
        pip install pymysql -t ${path.module}/layers/python/ --no-cache-dir --upgrade

        # 3. Zip while STRICTLY preserving permissions (-r = recursive, -q = quiet, -y = preserve symlinks)
        cd ${path.module}/layers
        zip -rqy db_driver.zip python/

        # 4. Clean up the unzipped folder
        rm -rf python/
    EOT
  }
}

resource "aws_lambda_layer_version" "rr_db_layer" {
  # Ensure the layer isn't created until the bash script finishes zipping
  depends_on = [null_resource.rr_build_and_clean_layer]

  filename            = "${path.module}/layers/db_driver.zip"
  layer_name          = "rr-${var.environment}-db-driver-layer"
  compatible_runtimes = ["python3.9"]
  description         = "RR: Database driver dependencies for secret rotation"

  # --- THE STABLE HASH FIX ---
  # We use the base64 sha256 hash of the build resource's ID.
  # This prevents "inconsistent result" errors because Terraform doesn't 
  # check the file on disk during the plan phase. It only updates 
  # if the null_resource (and its triggers) changes.
  source_code_hash = base64sha256(null_resource.rr_build_and_clean_layer.id)
}