import {
  Injectable,
  NotFoundException,
  BadRequestException,
} from '@nestjs/common';
import { User, createUser, Membership, Club } from '../entity/app.entity';
import { ClubsClientService } from './clubs-client.service';

@Injectable()
export class UsersService {
  //Using in-memory array to simulate database but irl, actual DB is used and async would be necessary
  private users: User[] = [
    { id: 1, name: 'Camilla' },
    { id: 2, name: 'Khang' },
  ];

  // Track user-club memberships
  private memberships: Membership[] = [];

  constructor(private readonly clubsClientService: ClubsClientService) {}

  async getUsers(): Promise<User[]> {
    return await Promise.resolve(this.users);
  }

  async findOne(name: string): Promise<User> {
    const user = this.users.find((u) => u.name === name);
    if (!user) {
      throw new NotFoundException(`User with name "${name}" does not exist`);
    }
    return await Promise.resolve(user);
  }

  async findOneById(id: number): Promise<User> {
    const user = this.users.find((u) => u.id === id);
    if (!user) {
      throw new NotFoundException(`User with id "${id}" does not exist`);
    }
    return await Promise.resolve(user);
  }

  async create(createUser: createUser): Promise<User> {
    const newUser = { ...createUser, id: this.users.length + 1 };
    this.users.push(newUser);
    return await Promise.resolve(newUser);
  }

  async joinClub(userId: number, clubName: string): Promise<Membership> {
    // Verify user exists
    const user = await this.findOneById(userId);

    // Call Clubs Service to verify club exists and get club info
    const club: Club = await this.clubsClientService.getClubByName(clubName);

    // Check if user is already a member of this club
    const existingMembership = this.memberships.find(
      (m) => m.userId === userId && m.clubId === club.id,
    );
    if (existingMembership) {
      throw new BadRequestException(
        `User "${user.name}" is already a member of club "${clubName}"`,
      );
    }

    // Create membership
    const membership: Membership = {
      userId,
      clubId: club.id,
      clubName: club.name,
    };
    this.memberships.push(membership);

    return await Promise.resolve(membership);
  }

  async getUserClubs(userId: number): Promise<Membership[]> {
    // Verify user exists
    await this.findOneById(userId);

    // Return all memberships for this user
    return await Promise.resolve(
      this.memberships.filter((m) => m.userId === userId),
    );
  }

  async markUnsubscribed(userID: number): Promise<User> {
    const user = this.users.find((u) => u.id === userID);
    if (!user) {
      throw new NotFoundException(`User with id "${userID}" does not exist`);
    }
    user.unsubscribed = true;
    return await Promise.resolve(user);
  }
}
