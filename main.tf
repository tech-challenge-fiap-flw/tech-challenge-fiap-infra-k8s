# Código temporário para deletar o alias KMS duplicado
resource "aws_kms_alias" "delete_temp" {
  name          = "alias/eks/tc-fiap-staging"
  target_key_id = "8099af9d-9c03-4b20-b26e-380bf698cb3d" # Substitua por um ID válido temporário
  lifecycle {
    prevent_destroy = false
  }
}