import axios from 'axios';
import {
  Injectable,
  BadRequestException,
  ServiceUnavailableException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';

// --- 1. Initial Default Code that works for dataflow3.ql ---
// export class AppService {
//   private readonly notificationsBaseUrl: string;

//   constructor(private readonly configService: ConfigService) {
//     const notificationsURL = this.configService.get<string>(
//       'NOTIFICATIONS_SERVICE_URL',
//     );
//     if (!notificationsURL) {
//       throw new Error(
//         'Critical Environment Variable NOTIFICATIONS_SERVICE_URL is missing!',
//       );
//     }
//     this.notificationsBaseUrl = notificationsURL;
//   }

//   async callEventDetailsNotif(eventId: string): Promise<{ message: string }> {
//     const url = `${this.notificationsBaseUrl}/notifications/event-update`;
//     const { data } = await axios.post(url);
//     return {
//       message: `Notifies when ${eventId} details has been modified: ${data}`,
//     };
//   }
// }
interface UserRoleResult {
  clubId: number;
  userId: number;
  role: string;
}

@Injectable()
export class AppService {
  private readonly notificationsBaseUrl: string;
  private readonly usersServiceBase: string;
  private readonly clubsServiceBase: string;

  constructor(private readonly configService: ConfigService) {
    this.notificationsBaseUrl = this.configService.get<string>('NOTIFICATIONS_SERVICE_URL') || '';
    this.usersServiceBase = this.configService.get<string>('USERS_SERVICE_URL') || '';
    this.clubsServiceBase = this.configService.get<string>('CLUBS_SERVICE_URL') || '';
  }

  async callEventDetailsNotif(eventId: string): Promise<{ message: string }> {
    const url = `${this.notificationsBaseUrl}/notifications/event-update`;
    const { data } = await axios.post(url);
    return { message: `Notifies when ${eventId} details has been modified: ${data}` };
  }

  async checkPermissions(userId: number, clubId: number): Promise<UserRoleResult> {
    if (!Number.isFinite(userId) || !Number.isFinite(clubId)) {
      throw new BadRequestException('Invalid userId or clubId');
    }
    try {
      const resp = await axios.get(`${this.clubsServiceBase}/clubs/roles/`);
      return resp.data;
    } catch (err: unknown) {
      if (axios.isAxiosError(err) && err.response?.status === 404) throw new BadRequestException('Club or user not found');
      throw new ServiceUnavailableException('Failed to fetch role from clubs');
    }
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

// --- 5. Public Readonly Properties Test ---
// Testing if dataflow3.ql works with public readonly instead of private
@Injectable()
export class PublicPropertyService {
  public readonly notificationsBaseURL: string;
  public readonly apiBaseURL: string;

  constructor(private readonly configService: ConfigService) {
    const notifURL = this.configService.get<string>('NOTIFICATIONS_SERVICE_URL');
    const apiURL = this.configService.get<string>('API_SERVICE_URL');
    
    if (!notifURL || !apiURL) {
      throw new Error('Required environment variables are missing!');
    }
    
    this.notificationsBaseURL = notifURL;
    this.apiBaseURL = apiURL;
  }

  async sendNotification(userId: string): Promise<void> {
    const url = `${this.notificationsBaseURL}/notify/${userId}`;
    await axios.post(url);
  }

  async fetchUserData(userId: string): Promise<any> {
    const endpoint = `${this.apiBaseURL}/users/${userId}`;
    const response = await axios.get(endpoint);
    return response.data;
  }
}

// --- 6. Simple Constant URL Test ---
const SIMPLE_API_URL = "https://api.example.com/v1/data";
axios.get(SIMPLE_API_URL);

// --- 7. Function Return Value Test ---
function buildApiEndpoint(resource: string): string {
  return `https://api.test.com/${resource}`;
}
const apiEndpoint = buildApiEndpoint("users");
axios.post(apiEndpoint);

// --- 8. Variable Reassignment Test ---
const originalUrl = "https://backend.service.com";
let mirrorUrl = originalUrl;
const finalUrl = mirrorUrl + "/api/status";
axios.get(finalUrl);