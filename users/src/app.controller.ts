// users/src/users.controller.ts
import {
  Controller,
  Get,
  Post,
  Patch,
  Param,
  Body,
  ParseIntPipe,
} from '@nestjs/common';
import { UsersService } from './users.service';
import type { createUser } from '../entity/app.entity';

@Controller('users')
export class UsersController {
  //Dependency Injection: automatically creates instance of UsersService and injects it into app
  constructor(private readonly usersService: UsersService) {}

  //correct controller methods
  @Get()
  async getUsers() {
    const users = await this.usersService.getUsers();
    return users;
  }
  //@Param() and @Body() need runtime values, not just TypeScript types
  @Get(':name')
  async findOne(@Param('name') name: string) {
    const single = await this.usersService.findOne(name);
    return single;
  }

  @Post()
  create(@Body() createUser: createUser) {
    return this.usersService.create(createUser);
  }

  @Post(':userId/join-club')
  async joinClub(
    @Param('userId', ParseIntPipe) userId: number,
    @Body() body: { clubName: string },
  ) {
    return await this.usersService.joinClub(userId, body.clubName);
  }

  @Get(':userId/clubs')
  async getUserClubs(@Param('userId', ParseIntPipe) userId: number) {
    return await this.usersService.getUserClubs(userId);
  }

  @Patch('unsubscribe/:userId')
  async markUnsubscribed(@Param('userId', ParseIntPipe) userID: number) {
    return await this.usersService.markUnsubscribed(userID);
  }
}
