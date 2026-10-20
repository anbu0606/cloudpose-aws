// CloudPose building blocks, written in TypeScript with Pulumi.
// Same ideas as infra/aws/bootstrap (S3) and infra/aws/app/ecr.tf (ECR),
// but in a real programming language: functions, loops, types.
import * as pulumi from "@pulumi/pulumi";
import * as aws from "@pulumi/aws";

const config = new pulumi.Config();
// Which environments to create. Change it with:  pulumi config set --path 'envs[0]' dev
const envs = config.getObject<string[]>("envs") ?? ["dev", "prod", "staging"];
const stack = pulumi.getStack(); // the stack name, e.g. "demo"

// Every resource gets the same tags (like default_tags in Terraform).
const tags = { Project: "cloudpose", ManagedBy: "pulumi", Owner: "anbu", Stack: stack };

// A plain TypeScript FUNCTION that builds a secure bucket. In HCL you'd write a module;
// here it's just a function you can call, test and reuse.
function secureBucket(name: string): aws.s3.Bucket {
  const bucket = new aws.s3.Bucket(name, { forceDestroy: true, tags });

  new aws.s3.BucketVersioning(`${name}-versioning`, {
    bucket: bucket.id,
    versioningConfiguration: { status: "Enabled" },
  });

  new aws.s3.BucketServerSideEncryptionConfiguration(`${name}-sse`, {
    bucket: bucket.id,
    rules: [{ applyServerSideEncryptionByDefault: { sseAlgorithm: "AES256" } }],
  });

  new aws.s3.BucketPublicAccessBlock(`${name}-public-block`, {
    bucket: bucket.id,
    blockPublicAcls: true,
    blockPublicPolicy: true,
    ignorePublicAcls: true,
    restrictPublicBuckets: true,
  });

  return bucket;
}

// A LOOP: one ECR repo + one artifacts bucket per environment.
// The same in Terraform needs for_each; here it's an ordinary for...of.
const repoUrls: Record<string, pulumi.Output<string>> = {};
const bucketNames: Record<string, pulumi.Output<string>> = {};

for (const env of envs) {
  const repo = new aws.ecr.Repository(`cloudpose-${env}`, {
    imageTagMutability: "IMMUTABLE", // a tag always means the same image
    imageScanningConfiguration: { scanOnPush: true },
    forceDelete: true, // let `pulumi destroy` remove it even if images exist
    tags,
  });

  new aws.ecr.LifecyclePolicy(`cloudpose-${env}-keep-5`, {
    repository: repo.name,
    policy: JSON.stringify({
      rules: [{
        rulePriority: 1,
        description: "Keep only the 5 newest images",
        selection: { tagStatus: "any", countType: "imageCountMoreThan", countNumber: 5 },
        action: { type: "expire" },
      }],
    }),
  });

  repoUrls[env] = repo.repositoryUrl;
  bucketNames[env] = secureBucket(`cloudpose-artifacts-${env}`).bucket;
}

// Outputs: like Terraform outputs, printed after `pulumi up` and read with `pulumi stack output`.
export const ecrRepositoryUrls = repoUrls;
export const artifactBuckets = bucketNames;
