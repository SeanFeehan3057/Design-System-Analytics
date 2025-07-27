# Design System Analytics Dashboard

A dashboard that tracks and visualizes the usage and impact of the Design System across different repositories.

## Features

- Tracks component usage across repositories
- Calculates hours saved through component reuse
- Shows adoption status for each repository
- Visualizes most impactful components

## Local Development

1. Clone the repository
2. Update `repos.txt` with the repositories you want to track
3. Run `measure-ds-impact.sh` to generate the data
4. Serve the files using a local web server (e.g., `python3 -m http.server 8000`)

## Deployment

The dashboard is automatically deployed to Vercel when changes are pushed to the main branch.

Current deployment: https://measure-ds-impact.vercel.app/ 