# tech-challenge-fiap-infra-k8s

Infraestrutura como código para o Tech Challenge FIAP usando Terraform e AWS EKS.

## Deploy Automático

O projeto utiliza GitHub Actions para deploy automático:

- **Main Branch**: Deploy para produção (workspace default).
- **Staging Branch**: Deploy para staging (workspace staging).

### Pré-requisitos

Configure os seguintes secrets no repositório GitHub:
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`

### Como funciona

O workflow `.github/workflows/deploy.yml` executa:
1. Checkout do código
2. Configuração do Terraform
3. Configuração das credenciais AWS
4. Terraform init, fmt, validate, plan
5. Terraform apply (apenas em push para main ou staging)