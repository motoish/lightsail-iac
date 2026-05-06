# lightsail-iac

## Settings: iam policy

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "LightsailAccess",
            "Effect": "Allow",
            "Action": [
                "lightsail:Get*",
                "lightsail:Create*",
                "lightsail:Delete*",
                "lightsail:Update*",
                "lightsail:Attach*",
                "lightsail:Detach*",
                "lightsail:OpenInstancePublicPorts",
                "lightsail:CloseInstancePublicPorts"
            ],
            "Resource": "*"
        },
        {
            "Sid": "AllowSTSIdentity",
            "Effect": "Allow",
            "Action": "sts:GetCallerIdentity",
            "Resource": "*"
        }
    ]
}
```
