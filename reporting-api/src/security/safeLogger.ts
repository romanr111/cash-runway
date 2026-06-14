export type SafeReportLogEvent = {
  reportId: string;
  category?: string;
  screen?: string;
  appVersion?: string;
  status: "created" | "duplicate" | "rate_limited" | "validation_failed" | "disabled" | "config_error" | "server_error";
  issueNumber?: number;
  durationMs: number;
};

export type SafeReportLogger = (event: SafeReportLogEvent) => void;

export const consoleSafeReportLogger: SafeReportLogger = (event) => {
  console.log(JSON.stringify({ event: "cash_runway_report", ...event }));
};
