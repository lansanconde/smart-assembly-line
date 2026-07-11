# Thing - representing logique du device dans IoT Core
# Un Thing par poste physique d'assemblage, avec un nom unique dans le compte AWS

resource "aws_iot_thing" "poste_1" {
  name = "poste_1"
}

# Certificate  X.509 — identité cryptographique du device
resource "aws_iot_certificate" "poste_1" {
  active = true  # Active = autorise à se connecter. Mettre fase =  révocation immédite si le device est compromis ou perdu
}

# Policy — autorisations strictes par device (least privilege)
# Un device ne peut publier que sur son propre topic
resource "aws_iot_policy" "device_policy" {
  name = "smart-assembly-device-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Autoriser la connexion avec son propre ClientId
        Effect   = "Allow"
        Action   = "iot:Connect"
        Resource = "arn:aws:iot:eu-west-3:169237360990:client/$${iot:ClientId}"
      },
      {
        # Publier uniquement sur son propre topic — isolation stricte entre postes
        Effect   = "Allow"
        Action   = "iot:Publish"
        Resource = "arn:aws:iot:eu-west-3:169237360990:topic/assembly-line/$${iot:ClientId}/metrics"
      },
      {
        # Accès au Device Shadow pour synchronisation état desired/reported
        Effect   = "Allow"
        Action   = ["iot:GetThingShadow", "iot:UpdateThingShadow"]
        Resource = "arn:aws:iot:eu-west-3:169237360990:thing/$${iot:ClientId}"
      }
    ]
  })
}

# Attacher la policy au certificat
resource "aws_iot_policy_attachment" "poste_1" {
  policy = aws_iot_policy.device_policy.name
  target = aws_iot_certificate.poste_1.arn
}

# Attacher le certificat au Thing
resource "aws_iot_thing_principal_attachment" "poste_1" {
  thing     = aws_iot_thing.poste_1.name
  principal = aws_iot_certificate.poste_1.arn
}