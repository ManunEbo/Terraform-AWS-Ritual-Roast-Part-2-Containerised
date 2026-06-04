import { NextResponse } from 'next/server';

export async function GET() {
  return NextResponse.json({ status: 'ok', tier: 'frontend' }, { status: 200 });
}
