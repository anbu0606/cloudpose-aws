// The same building blocks as the Pulumi program: per environment, one ECR repo + one
// secure S3 bucket. Notice how much shorter it is: CDK "constructs" bundle good
// defaults (L2 constructs). One line of `blockPublicAccess` becomes a whole resource.
import * as cdk from "aws-cdk-lib";
import * as ecr from "aws-cdk-lib/aws-ecr";
import * as s3 from "aws-cdk-lib/aws-s3";
import { Construct } from "constructs";

export interface CloudPoseStackProps extends cdk.StackProps {
  envs: string[];
}

export class CloudPoseStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props: CloudPoseStackProps) {
    super(scope, id, props);

    for (const env of props.envs) {
      const repo = new ecr.Repository(this, `Repo-${env}`, {
        imageTagMutability: ecr.TagMutability.IMMUTABLE, // a tag always means the same image
        imageScanOnPush: true,
        emptyOnDelete: true, // destroy also deletes images (demo only)
        removalPolicy: cdk.RemovalPolicy.DESTROY, // default would KEEP it after destroy
        lifecycleRules: [{ maxImageCount: 5, description: "Keep only the 5 newest images" }],
      });

      const bucket = new s3.Bucket(this, `Artifacts-${env}`, {
        versioned: true,
        encryption: s3.BucketEncryption.S3_MANAGED,
        blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
        enforceSSL: true, // adds the "deny non-HTTPS" bucket policy for you
        removalPolicy: cdk.RemovalPolicy.DESTROY,
        autoDeleteObjects: true, // demo only: empties the bucket on destroy
      });

      // Outputs show up after `cdk deploy` (CloudFormation stack outputs).
      new cdk.CfnOutput(this, `EcrUrl-${env}`, { value: repo.repositoryUri });
      new cdk.CfnOutput(this, `Bucket-${env}`, { value: bucket.bucketName });
    }
  }
}
