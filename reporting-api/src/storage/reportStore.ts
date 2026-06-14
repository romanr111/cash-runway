export type ReportStore = {
  getJson<T>(key: string): Promise<T | undefined>;
  setJson<T>(key: string, value: T, ttlSeconds: number): Promise<void>;
  setJsonIfAbsent<T>(key: string, value: T, ttlSeconds: number): Promise<boolean>;
  delete(key: string): Promise<void>;
  increment(key: string, ttlSeconds: number): Promise<number>;
};

type Entry = {
  value: unknown;
  expiresAt: number;
};

export class MemoryReportStore implements ReportStore {
  private readonly entries = new Map<string, Entry>();

  constructor(private readonly now: () => number = Date.now) {}

  async getJson<T>(key: string): Promise<T | undefined> {
    const entry = this.entries.get(key);
    if (!entry || entry.expiresAt <= this.now()) {
      this.entries.delete(key);
      return undefined;
    }
    return entry.value as T;
  }

  async setJson<T>(key: string, value: T, ttlSeconds: number): Promise<void> {
    this.entries.set(key, { value, expiresAt: this.now() + ttlSeconds * 1000 });
  }

  async setJsonIfAbsent<T>(key: string, value: T, ttlSeconds: number): Promise<boolean> {
    if (await this.getJson(key) !== undefined) {
      return false;
    }
    await this.setJson(key, value, ttlSeconds);
    return true;
  }

  async delete(key: string): Promise<void> {
    this.entries.delete(key);
  }

  async increment(key: string, ttlSeconds: number): Promise<number> {
    const current = await this.getJson<number>(key);
    const next = (current ?? 0) + 1;
    await this.setJson(key, next, ttlSeconds);
    return next;
  }
}

export type UpstashReportStoreConfig = {
  restUrl: string;
  token: string;
  keyPrefix?: string;
};

export class UpstashReportStore implements ReportStore {
  private readonly keyPrefix: string;

  constructor(private readonly config: UpstashReportStoreConfig) {
    this.keyPrefix = config.keyPrefix ?? "cash-runway:reports";
  }

  async getJson<T>(key: string): Promise<T | undefined> {
    const result = await this.command<string | null>(["GET", this.key(key)]);
    return result ? JSON.parse(result) as T : undefined;
  }

  async setJson<T>(key: string, value: T, ttlSeconds: number): Promise<void> {
    await this.command<string>(["SET", this.key(key), JSON.stringify(value), "EX", ttlSeconds]);
  }

  async setJsonIfAbsent<T>(key: string, value: T, ttlSeconds: number): Promise<boolean> {
    const result = await this.command<string | null>([
      "SET",
      this.key(key),
      JSON.stringify(value),
      "EX",
      ttlSeconds,
      "NX"
    ]);
    return result === "OK";
  }

  async delete(key: string): Promise<void> {
    await this.command<number>(["DEL", this.key(key)]);
  }

  async increment(key: string, ttlSeconds: number): Promise<number> {
    const redisKey = this.key(key);
    const count = await this.command<number>(["INCR", redisKey]);
    if (count === 1) {
      await this.command<number>(["EXPIRE", redisKey, ttlSeconds]);
    }
    return count;
  }

  private key(key: string): string {
    return `${this.keyPrefix}:${key}`;
  }

  private async command<T>(command: unknown[]): Promise<T> {
    const response = await fetch(this.config.restUrl, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${this.config.token}`,
        "Content-Type": "application/json"
      },
      body: JSON.stringify(command)
    });
    const payload = await response.json() as { result?: T; error?: string };
    if (!response.ok || payload.error) {
      throw new Error(payload.error ?? `Upstash command failed: ${response.status}`);
    }
    return payload.result as T;
  }
}
