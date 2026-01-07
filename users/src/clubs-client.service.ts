import { Injectable, HttpException, HttpStatus } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { HttpService } from '@nestjs/axios';
import { firstValueFrom } from 'rxjs';
import { Club } from '../entity/app.entity';

@Injectable()
export class ClubsClientService {
  private readonly clubsServiceUrl: string;

  constructor(
    private readonly httpService: HttpService,
    private readonly configService: ConfigService,
  ) {
    const clubsURL = this.configService.get<string>('CLUBS_SERVICE_URL');
    if (!clubsURL) {
      throw new Error(
        'Critical Environment Variable CLUBS_SERVICE_URL is missing!',
      );
    }
    this.clubsServiceUrl = clubsURL;
  }

  async getClubByName(name: string): Promise<Club> {
    try {
      const response = await firstValueFrom(
        this.httpService.get<Club>(`${this.clubsServiceUrl}/clubs/${name}`),
      );
      return response.data;
    } catch (error: unknown) {
      if (
        error &&
        typeof error === 'object' &&
        'response' in error &&
        error.response &&
        typeof error.response === 'object' &&
        'status' in error.response &&
        error.response.status === 404
      ) {
        throw new HttpException(
          `Club with name "${name}" does not exist`,
          HttpStatus.NOT_FOUND,
        );
      }
      throw new HttpException(
        'Failed to communicate with Clubs Service',
        HttpStatus.SERVICE_UNAVAILABLE,
      );
    }
  }

  async getClubById(id: number): Promise<Club> {
    try {
      // Note: Clubs service currently finds by name, but we can add this if needed
      // For now, we'll get all clubs and find by id
      const response = await firstValueFrom(
        this.httpService.get<Club[]>(`${this.clubsServiceUrl}/clubs`),
      );
      const club = response.data.find((c) => c.id === id);
      if (!club) {
        throw new HttpException(
          `Club with id "${id}" does not exist`,
          HttpStatus.NOT_FOUND,
        );
      }
      return club;
    } catch (error) {
      if (error instanceof HttpException) {
        throw error;
      }
      throw new HttpException(
        'Failed to communicate with Clubs Service',
        HttpStatus.SERVICE_UNAVAILABLE,
      );
    }
  }
}
