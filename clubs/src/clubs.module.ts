import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { ClubsController } from './clubs.controller';
import { ClubsService } from './clubs.service';
import { MembersModule } from './members/members.module';

@Module({
  imports: [ConfigModule.forRoot({ isGlobal: true }), MembersModule],
  controllers: [ClubsController],
  providers: [ClubsService],
})
export class AppModule {}
