import axios from 'axios';
import { ConfigService } from '@nestjs/config';

// --- 1. Initial Default Code that works for dataflow3.ql ---
export class AppService {
  private readonly notificationsBaseUrl: string;

  constructor(private readonly configService: ConfigService) {
    const notificationsURL = this.configService.get<string>(
      'NOTIFICATIONS_SERVICE_URL',
    );
    if (!notificationsURL) {
      throw new Error(
        'Critical Environment Variable NOTIFICATIONS_SERVICE_URL is missing!',
      );
    }
    this.notificationsBaseUrl = notificationsURL;
  }

  async callEventDetailsNotif(eventId: string): Promise<{ message: string }> {
    const url = `${this.notificationsBaseUrl}/notifications/event-update`;
    const { data } = await axios.post(url);
    return {
      message: `Notifies when ${eventId} details has been modified: ${data}`,
    };
  }
}

// --- 2. Assignment Chains & If-Else (Equivalence Classes) ---
let branchUrl;
if (process.env.NODE_ENV === 'prod') {
    branchUrl = "{PROD_URL}"; 
} else {
    branchUrl = "{DEV_URL}";  
}
axios.get(`${branchUrl}/health`);

// --- 3. Integer Handling & Arithmetic ---
const BASE_PORT = 8000;
const port = BASE_PORT + 10;
const url = `http://localhost:${port}/status`;
axios.get(url);

// --- 4. Termination & Loops ---
let loopedUrl = "base";
for (let i = 0; i < 3; i++) {
    loopedUrl += "/path"; 
}
axios.get(loopedUrl);