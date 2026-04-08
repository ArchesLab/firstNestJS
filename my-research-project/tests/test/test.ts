import axios from 'axios';
import {
  Injectable,
  BadRequestException,
  ServiceUnavailableException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';

interface UserRoleResult {
  clubId: number;
  userId: number;
  role: string;
}
// TEST1: Basic URL Construction & Environment Variables
@Injectable()
export class AppService {
  private readonly notificationsBaseUrl: string;
  private readonly usersServiceBase: string;
  private readonly clubsServiceBase: string;

  constructor(private readonly configService: ConfigService) {
    const notifURL = this.configService.get<string>('TEST1_NOTIF__SERVICE_URL') || '';
    const userURL = this.configService.get<string>('TEST1_USERS_SERVICE_URL') || '';
    const clubURL = this.configService.get<string>('TEST1CLUBS_SERVICE_URL') || '';

     this.notificationsBaseUrl = notifURL;
     this.usersServiceBase = userURL;
     this.clubsServiceBase = clubURL;

    if (!notifURL || !userURL || !clubURL) {
      throw new Error('Required environment variables are missing!');
    }
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

// --- 2. Assignment Chains & If-Else (Equivalence Classes) - PASS ---
let branchUrl;
if (process.env.NODE_ENV === 'prod') {
    branchUrl = "TEST2PROD_SERVICE_URL"; 
} else {
    branchUrl = "TEST2DEV_SERVICE_URL";  
}
axios.get(`${branchUrl}/health`);

// --- 3. One Higher Level Function - PASS ---
let branch;
function setBranchUrl() {
  return 'TEST3_URL';

}
branch = setBranchUrl();  
axios.get(`${branch}/health/test3`);

// --- 4. Integer Handling & Arithmetic (PASS) ---
const BASE_HOST = "http://localhost";
const BASE_PORT = 8000;
const port = BASE_PORT + 10;
const url = `${BASE_HOST}:${port}/TEST4/status`;
axios.get(url);

// --- 5. String Concatenation (PASS) ---
const BASE_HOST2 = "http://localhost";
const BASE_PORT2 = 8000;
const port2 = BASE_PORT2 + 'hi';
const url2 = `${BASE_HOST2}:${port2}/TEST5/status`;
axios.get(url2);

// --- 6. Termination & Loops (FAIL) ---
let loopedUrl = "test6/path";
for (let i = 0; i < 3; i++) {
    loopedUrl += "/base"; 
}
axios.get(loopedUrl);

// --- 7. URL has parameter - PASS ---
// Testing if dataflow3.ql works with public readonly instead of private
@Injectable()
export class PublicPropertyService {
  private readonly notificationsBaseURL: string;
  private readonly apiBaseURL: string;

  constructor(private readonly configService: ConfigService) {
    const notifURL = this.configService.get<string>('TEST7_SERVICE_URL') || ''; 
    const apiURL = this.configService.get<string>('TEST7_SERVICE_URL') || '';
    
    this.notificationsBaseURL = notifURL;
    this.apiBaseURL = apiURL;

    if (!notifURL || !apiURL) {
      throw new Error('Required environment variables are missing!');
    }
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

// --- 8. Simple Constant URL Test PASS ---
const SIMPLE_API_URL = "https://api.example.com/test8";
axios.get(SIMPLE_API_URL);

// --- 9. Function Return Value Test PASS ---
function buildApiEndpoint(resource: string): string {
  return `https://test9/${resource}`;
}
const apiEndpoint = buildApiEndpoint("users");
axios.post(apiEndpoint);

// --- 10. Variable Reassignment Test - PASS---
const originalUrl = "https://backend/test10";
let mirrorUrl = originalUrl;
const finalUrl = mirrorUrl + "/api";
axios.get(finalUrl);

// --- 11. Mutable Assignemntns via no readonly - PASS---
@Injectable()
export class AppService2 {
  private test9NotificationsBase: string;
  private test9UsersBase: string;
  private test9ClubsBase: string;

  constructor(private readonly configService: ConfigService) {
    this.test9NotificationsBase = this.configService.get<string>('TEST11_NOTIFICATIONS_SERVICE_URL') || '';
    this.test9UsersBase = this.configService.get<string>('TEST11_USERS_SERVICE_URL') || '';
    this.test9ClubsBase = this.configService.get<string>('TEST11_CLUBS_SERVICE_URL') || '';
  }

  async callEventDetailsNotif(eventId: string): Promise<{ message: string }> {
    const url = `${this.test9NotificationsBase}/notifications`;
    const { data } = await axios.post(url);
    return { message: `Notifies when ${eventId} details has been modified: ${data}` };
  }

  async checkPermissions(userId: number, clubId: number): Promise<UserRoleResult> {
    if (!Number.isFinite(userId) || !Number.isFinite(clubId)) {
      throw new BadRequestException('Invalid userId or clubId');
    }
    try {
      const resp = await axios.get(`${this.test9ClubsBase}/clubs`);
      return resp.data;
    } catch (err: unknown) {
      if (axios.isAxiosError(err) && err.response?.status === 404) throw new BadRequestException('Club or user not found');
      throw new ServiceUnavailableException('Failed to fetch role from clubs');
    }
  }
}

// --- 12. Changing private to public - PASS---
@Injectable()
export class AppService3 {
  public readonly test10NotificationsBase: string;
  public readonly test10UsersBase: string;
  public readonly test10ClubsBase: string;

  constructor(private readonly configService: ConfigService) {
    this.test10NotificationsBase = this.configService.get<string>('TEST12_NOTIFICATIONS_SERVICE_URL') || '';
    this.test10UsersBase = this.configService.get<string>('TEST12_USERS_SERVICE_URL') || '';
    this.test10ClubsBase = this.configService.get<string>('TEST12_CLUBS_SERVICE_URL') || '';
  }

  async callEventDetailsNotif(eventId: string): Promise<{ message: string }> {
    const url = `${this.test10NotificationsBase}/notifications`;
    const { data } = await axios.post(url);
    return { message: `Notifies when ${eventId} details has been modified: ${data}` };
  }
}

// --- 13. Including Promise - FAIL---
async function callbackFlow(configService: ConfigService) {
    const rawUrl = configService.get('TEST13_SERVICE_URL');
    Promise.resolve(rawUrl).then(url => {
        axios.get(url);
    });
}

// --- 14. Outputs both possibilities, default and API_URL) - PASS---
async function shortCircuitTest(configService: ConfigService) {
    const input = configService.get('TEST14_API_URL');
    const url = input || "http://default.com";
    await axios.get(url);
}

// --- 15. Inheritance - PASS---
class BaseService {
  public readonly apiUrl: string;

  constructor(config: ConfigService) {
    this.apiUrl = config.get('TEST15_RANDOM_URL') || '';
  }
}

@Injectable()
export class SubService extends BaseService {
  constructor(configService: ConfigService) {
    super(configService);
  }

  async callApi() {
    await axios.get(this.apiUrl);
  }
}

// --- 16. URL has parameter --- PASS ---
@Injectable()
export class PublicPropertyService2 {
  private readonly test15BaseURL: string;
  private readonly test15APIaseURL: string;

  constructor(private readonly configService: ConfigService) {
    const notifURL = this.configService.get<string>('TEST16_NOTIFICATIONS_SERVICE_URL') || ''; 
    const apiURL = this.configService.get<string>('TEST16_API_SERVICE_URL') || '';
    
    this.test15BaseURL = notifURL;
    this.test15APIaseURL = apiURL;

    if (!notifURL || !apiURL) {
      throw new Error('Required environment variables are missing!');
    }
  }

  async sendNotification(userId: string): Promise<void> {
    const url = `${this.test15BaseURL}/notify/${userId}`;
    await axios.post(url);
  }

  async fetchUserData(userId: string): Promise<any> {
    const endpoint = `${this.test15APIaseURL}/users/${userId}`;
    const response = await axios.get(endpoint);
    return response.data;
  }
}
// --- 17. Recursion/Function Calls - FAIL due to session timeout ---
// function getPath(depth: number): string {
//     if (depth <= 0) {
//         return "TEST17_BASE_URL";
//     }
//     return getPath(depth - 1) + "/sub";
// }

// function test() {
//     // Expected result: "TEST15_BASE_URL/sub/health"
//     //const url = getPath(1); 
//     //axios.get(`${url}/health`);
// }
