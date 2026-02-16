const express = require('express');
const multer = require('multer');
const cors = require('cors');
const path = require('path');
const fs = require('fs');

const app = express();
const PORT = process.env.PORT || 3000;

// Middleware
app.use(cors());
app.use(express.json());
app.use((req, res, next) => {
    console.log(`${new Date().toISOString()} - ${req.method} ${req.url}`);
    next();
});
app.use('/uploads', express.static(path.join(__dirname, 'uploads')));

// Ensure uploads directory exists
const uploadDir = path.join(__dirname, 'uploads');
if (!fs.existsSync(uploadDir)) {
    fs.mkdirSync(uploadDir, { recursive: true });
}

// Multer configuration for file uploads
const storage = multer.diskStorage({
    destination: (req, file, cb) => {
        cb(null, 'uploads/');
    },
    filename: (req, file, cb) => {
        const uniqueSuffix = Date.now() + '-' + Math.round(Math.random() * 1E9);
        cb(null, uniqueSuffix + path.extname(file.originalname));
    }
});

const upload = multer({ storage: storage });

// Database simulation (JSON file)
const DB_FILE = path.join(__dirname, 'milestones_db.json');

const getDatabase = () => {
    if (!fs.existsSync(DB_FILE)) return [];
    try {
        const data = fs.readFileSync(DB_FILE, 'utf8');
        return JSON.parse(data);
    } catch (e) {
        return [];
    }
};

const saveToDatabase = (data) => {
    fs.writeFileSync(DB_FILE, JSON.stringify(data, null, 2));
};

// API Endpoints
app.get('/api/milestones', (req, res) => {
    const milestones = getDatabase();
    res.json(milestones);
});

app.delete('/api/milestones/:id', (req, res) => {
    try {
        const id = req.params.id;
        console.log(`\n[DELETE] Request for ID: ${id}`);
        let db = getDatabase();
        
        console.log(`Current DB size: ${db.length}`);
        const initialLength = db.length;
        
        // 1. Try to delete by exact ID
        db = db.filter(m => String(m.id) !== String(id));
        
        // 2. Fallback: If not found by ID, search the object being deleted (if client could provide more info)
        // But for now, if the delete failed, let's look at what's in the DB to help debug
        if (db.length === initialLength) {
            console.log(`Milestone with ID ${id} not found.`);
            // Optionally: Clear database entry if it matches title/date/owner in case of ID mismatch from previous version
            // For now, return 404 with ID list for debugging
            const allIds = getDatabase().map(m => m.id);
            console.log('Available IDs in DB:', allIds);
            return res.status(404).json({ 
                error: 'Milestone not found', 
                requestedId: id,
                dbIds: allIds 
            });
        }
        
        saveToDatabase(db);
        console.log(`Successfully deleted milestone with ID: ${id}. New size: ${db.length}`);
        res.json({ message: 'Deleted successfully' });
    } catch (error) {
        console.error('Delete error:', error);
        res.status(500).json({ error: 'Internal server error' });
    }
});

app.post('/api/milestones', upload.array('images'), (req, res) => {
    try {
        console.log('\n--- New Upload Request ---');
        let eventData = {};
        
        if (req.body.event) {
            try {
                eventData = typeof req.body.event === 'string' ? JSON.parse(req.body.event) : req.body.event;
            } catch (e) {
                eventData = req.body;
            }
        } else {
            eventData = req.body;
        }

        const protocol = req.headers['x-forwarded-proto'] || req.protocol;
        const host = req.get('host');
        const baseUrl = `${protocol}://${host}`;
        const imageUrls = req.files ? req.files.map(file => `${baseUrl}/uploads/${file.filename}`) : [];

        // Combine metadata with image URLs
        // FIX: Use the client ID if provided so frontend and backend stay in sync
        const newMilestone = {
            id: eventData.id || Date.now().toString(),
            title: eventData.title || 'Untitled',
            description: eventData.description || '',
            date: eventData.date || new Date().toISOString(),
            owner: eventData.owner !== undefined ? parseInt(eventData.owner) : 2,
            images: imageUrls,
            createdAt: new Date().toISOString()
        };

        console.log('Saving milestone with ID:', newMilestone.id);

        const db = getDatabase();
        db.push(newMilestone);
        saveToDatabase(db);

        res.status(201).json({
            message: 'Milestone created successfully',
            milestone: newMilestone,
            imageUrls: imageUrls
        });
    } catch (error) {
        console.error('SERVER ERROR:', error);
        res.status(500).json({ error: 'Internal server error', details: error.message });
    }
});

app.listen(PORT, '0.0.0.0', () => {
    console.log(`Server is running on http://localhost:${PORT}`);
    console.log(`Uploads available at http://localhost:${PORT}/uploads`);
});
