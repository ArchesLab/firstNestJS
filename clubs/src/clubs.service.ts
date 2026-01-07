/* eslint-disable prettier/prettier */
import { Injectable, NotFoundException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import axios from 'axios';
import { Club, createClub, updateClub } from '../entity/app.entity';

@Injectable()
export class ClubsService {
  private readonly eventsServiceBase: string;

  constructor(private readonly configService: ConfigService) {
    const eventsURL = this.configService.get<string>('EVENTS_SERVICE_URL');
    if (!eventsURL) {
      throw new Error('Critical Environment Variable EVENTS_SERVICE_URL is missing!');
    }
    this.eventsServiceBase = eventsURL;
  }

  //Using in-memory array to simulate database but irl, actual DB is used and async would be necessary
  private clubs: Club[] = [
    { id: 1, name: 'ACM' },
    { id: 2, name: 'UCLA SWE' },
  ];
  async getClubs(): Promise<Club[]> {
    return await Promise.resolve(this.clubs);
  }

  async findOne(name: string): Promise<Club> {
    const club = this.clubs.find((c) => c.name === name);
    if (!club) {
      throw new NotFoundException(`Club with name "${name}" does not exist`);
    }
    return await Promise.resolve(club);
  }

  async create(createClub: createClub): Promise<Club> {
    const newClub = { ...createClub, id: this.clubs.length + 1 };
    this.clubs.push(newClub);
    return await Promise.resolve(newClub);
  }

  async update(id: number, update: updateClub): Promise<Club> {
    const index = this.clubs.findIndex((c) => c.id === id);
    if (index === -1) {
      throw new NotFoundException(`Club with id "${id}" does not exist`);
    }
    const existing = this.clubs[index];
    const updated: Club = { ...existing, ...update };
    this.clubs[index] = updated;
    return await Promise.resolve(updated);
  }

  async removeEventReference(
    eventId: number,
  ): Promise<{ removed: boolean; eventId: number }> {
    // In a real implementation you would locate clubs referencing this event and remove the event from event list associated with club.
    // Here we just simulate success.
    return await Promise.resolve({ removed: true, eventId });
  }

  private readonly roles: Record<number, Record<number, string>> = {
    // clubId -> userId -> role
    1: { 1: 'officer', 2: 'member' },
    2: { 2: 'officer' },
  };

  async createEventForClub(clubId: number, payload: { title: string },): Promise<{ id: number; clubId: number; title: string }> {
    const clubExists = this.clubs.some((c) => c.id === clubId);
    if (!clubExists) {
      throw new NotFoundException(`Club with id "${clubId}" does not exist`);
    }
    const url = `${this.eventsServiceBase}/events`;
    const response = await axios.post<{
      id: number;
      clubId: number;
      title: string;
    }>(url, {
      clubId,
      title: payload.title,
    });
    return {
      id: response.data.id,
      clubId: response.data.clubId,
      title: response.data.title,
    };
  }

  getUserRole(clubId: number, userId: number): { clubId: number; userId: number; role: string } {
    const clubExists = this.clubs.some((c) => c.id === clubId);
    if (!clubExists) {
      throw new NotFoundException(`Club with id "${clubId}" does not exist`);
    }
    const role = this.roles[clubId]?.[userId] || 'none';
    return { clubId, userId, role };
  }
}
