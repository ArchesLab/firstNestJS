// users/entity/app.entity.ts

export interface User {
  id: number;
  name: string;
  unsubscribed?: boolean;
}

export interface createUser {
  name: string;
}

export interface Club {
  id: number;
  name: string;
}

export interface Membership {
  userId: number;
  clubId: number;
  clubName: string;
}
