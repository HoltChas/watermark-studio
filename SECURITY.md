# Security

## Reporting

Please do not open public issues with private videos, model paths, personal file paths, or sensitive logs.

For now, report security-sensitive issues privately to the repository maintainers. If private reporting is not available yet, open a minimal public issue that describes the affected component without attaching private media or logs.

## Supported Versions

Watermark Studio is currently a developer preview. Security fixes target the latest code on the main branch.

## Media Handling

Watermark Studio processes local video files and can create large temporary frame directories. Review paths carefully before running cleanup jobs, especially when using `--work-dir`.
