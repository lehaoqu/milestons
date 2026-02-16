# Milestones Backend

A simple Node.js/Express server to handle JSON metadata and image uploads for the 情侣里程碑 (Milestones) app.

## Features

- Receive `multipart/form-data` uploads.
- Save images locally in the `uploads/` folder.
- Store milestone metadata in a local `milestones_db.json` file.
- Serve static images via `/uploads`.

## Setup

1. Install dependencies:
   ```bash
   npm install
   ```

2. Start the server:
   ```bash
   npm start
   ```

3. The server will be running at `http://localhost:3000`.

## API Endpoints

### POST `/api/milestones`
- **Body**: `multipart/form-data`
- **Fields**:
  - `event`: JSON string containing milestone data (title, description, date, owner).
  - `images`: Binary file(s).
- **Returns**: JSON with the newly created milestone and public image URLs.

### GET `/api/milestones`
- **Returns**: Array of all stored milestones.

## Notes for App Connection
If testing on a physical mobile device, replace `localhost` in your Flutter app with your machine's local IP address (e.g., `192.168.1.x`).
