# aws

AWS CLI v2 with network access to AWS services.

## Usage

```nix
{ plugins = [ "aws" ]; }
```

## What it provides

| Category | Details |
|---|---|
| **Packages** | `awscli2` |
| **Domains** | `amazonaws.com`, `aws.amazon.com` |

## Configuration

Pass credentials/profile via `env` in your project config:

```nix
{
  plugins = [ "aws" ];
  env = {
    AWS_REGION = "eu-west-1";
    AWS_PROFILE = "my-profile";
  };
}
```
