import axios from 'axios';
// --- 1. Trivial & Basic ---
const basicUrl = "http://localhost:3000";
axios.get(basicUrl);

// --- 2. Assignment Chains & If-Else (Equivalence Classes) ---
let branchUrl;
if (process.env.NODE_ENV === 'prod') {
    branchUrl = "{PROD_URL}"; // Case A
} else {
    branchUrl = "{DEV_URL}";  // Case B
}
axios.get(`${branchUrl}/health`);

// --- 3. Integer Handling & Arithmetic ---
const BASE_PORT = 8000;
const port = BASE_PORT + 10; // Result: 8010
axios.get(`http://localhost:${port}/status`);

// --- 4. Termination & Loops (Testing Recursion limits) ---
let loopedUrl = "base";
for (let i = 0; i < 3; i++) {
    loopedUrl += "/path"; // Does it handle 10 additions or stop early?
}
axios.get(loopedUrl);