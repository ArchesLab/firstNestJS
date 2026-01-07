import {
  Injectable,
  BadRequestException,
  ServiceUnavailableException,
} from '@nestjs/common';
import axios from 'axios';
import { ConfigService } from '@nestjs/config';

interface RegisterPayload {
  name: string;
  email?: string; // optional stub for future
  password?: string; // optional stub; not stored here
}

interface CreatedUser {
  id: number;
  name: string;
}

interface UserRoleResult {
  clubId: number;
  userId: number;
  role: string;
}

@Injectable()
export class AppService {
  private readonly usersServiceBase: string;
  private readonly clubsServiceBase: string;

  constructor(private readonly configService: ConfigService) {
    const usersUrl = this.configService.get<string>('USERS_SERVICE_URL');
    const clubsUrl = this.configService.get<string>('CLUBS_SERVICE_URL');
    if (!usersUrl || !clubsUrl) {
      throw new Error('Critical Environment Variables are missing!');
    }
    this.usersServiceBase = usersUrl;
    this.clubsServiceBase = clubsUrl;
  }
  getHello(): string {
    return 'Hello World!';
  }
  async register(payload: RegisterPayload): Promise<{ user: CreatedUser }> {
    if (!payload.name || payload.name.trim().length === 0) {
      throw new BadRequestException('Name is required');
    }
    // Simulate auth account creation (hash password etc.) omitted for brevity
    try {
      const response = await axios.post<CreatedUser>(
        `${this.usersServiceBase}/users`,
        { name: payload.name.trim() },
      );
      return { user: response.data };
    } catch (err: unknown) {
      if (axios.isAxiosError(err) && err.response?.status === 409) {
        throw new BadRequestException('User already exists');
      }
      throw new ServiceUnavailableException('Failed to create user profile');
    }
  }

  async checkPermissions(
    userId: number,
    clubId: number,
  ): Promise<UserRoleResult> {
    if (!Number.isFinite(userId) || !Number.isFinite(clubId)) {
      throw new BadRequestException('Invalid userId or clubId');
    }
    try {
      const resp = await axios.get<UserRoleResult>(
        `${this.clubsServiceBase}/clubs/roles/${clubId}/${userId}`,
      );
      return resp.data;
    } catch (err: unknown) {
      if (axios.isAxiosError(err) && err.response?.status === 404) {
        throw new BadRequestException('Club or user not found');
      }
      throw new ServiceUnavailableException('Failed to fetch role from clubs');
    }
  }
}
