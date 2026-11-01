// src/lib/api_error.ts
export class ApiError extends Error {
  constructor(
    message: string,
    public readonly status?: number,
    public readonly code?: string,
  ) {
    super(message);
    this.name = "ApiError";
  }
}

/** A 2xx whose body is not what the endpoint promises (HTML, wrong type, missing fields). */
export const BAD_RESPONSE = "Máy chủ trả về dữ liệu không hợp lệ. Vui lòng thử lại sau.";

export const badResponse = (status?: number) => new ApiError(BAD_RESPONSE, status, "bad_response");

/** Text for the admin. Anything but an ApiError is a bug or a browser message in English, so it is never shown. */
export function describeError(error: unknown): string {
  return error instanceof ApiError ? error.message : "Đã có lỗi xảy ra. Vui lòng thử lại.";
}
