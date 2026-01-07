// gateway/src/app.service.ts
import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import axios from 'axios';
import { User, Club } from './types';

@Injectable()
export class AppService {
  private readonly usersServiceBase: string;
  private readonly clubsServiceBase: string;

  constructor(private readonly configService: ConfigService) {
    const usersURL = this.configService.get<string>('USERS_SERVICE_URL');
    const clubsURL = this.configService.get<string>('CLUBS_SERVICE_URL');
    if (!usersURL || !clubsURL) {
      throw new Error(
        'Critical Environment Variable USERS_SERVICE_URL or CLUBS_SERVICE_URL is missing!',
      );
    }
    this.usersServiceBase = usersURL;
    this.clubsServiceBase = clubsURL;
  }

  async getUsers(): Promise<User[]> {
    const res = await axios.get<User[]>(`${this.usersServiceBase}/users`);
    return res.data;
  }

  async getClubs(): Promise<Club[]> {
    const res = await axios.get<Club[]>(`${this.clubsServiceBase}/clubs`);
    return res.data;
  }
}
