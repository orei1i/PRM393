using System;
using System.Collections.Generic;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;

namespace DomainLayer.Helpers
{
    /// <summary>Hàm thuần cho RAG: chuẩn hoá, cắt đoạn, băm, phép tính vector.</summary>
    public static class RagText
    {
        public const int DefaultChunkSize = 800;
        public const int DefaultOverlap = 100;

        public static string Normalize(string? text)
        {
            if (string.IsNullOrEmpty(text)) return string.Empty;
            var unified = text.Normalize(NormalizationForm.FormC).Replace("\r\n", "\n").Replace('\r', '\n');
            unified = Regex.Replace(unified, @"[^\S\n]+", " ");
            unified = Regex.Replace(unified, @"\n{3,}", "\n\n");
            return unified.Trim();
        }

        public static string Hash(string normalized)
        {
            var bytes = SHA256.HashData(Encoding.UTF8.GetBytes(normalized));
            return Convert.ToHexString(bytes).ToLowerInvariant();
        }

        /// <summary>Cắt theo cửa sổ trượt, ưu tiên ngắt ở cuối đoạn hoặc cuối câu, các đoạn chồng nhau.</summary>
        public static List<string> Chunk(string normalized, int size = DefaultChunkSize, int overlap = DefaultOverlap)
        {
            if (size <= 0 || overlap < 0 || overlap >= size)
            {
                throw new ArgumentOutOfRangeException(nameof(overlap), "Cần 0 <= overlap < size.");
            }

            var chunks = new List<string>();
            var start = 0;
            while (start < normalized.Length)
            {
                var end = Math.Min(start + size, normalized.Length);
                if (end < normalized.Length)
                {
                    end = FindBreak(normalized, start, end, size);
                }

                var piece = normalized.Substring(start, end - start).Trim();
                if (piece.Length > 0) chunks.Add(piece);
                if (end >= normalized.Length) break;
                start = Math.Max(end - overlap, start + 1);
            }

            return chunks;
        }

        private static int FindBreak(string text, int start, int end, int size)
        {
            var minEnd = start + size / 2;
            var paragraph = text.LastIndexOf("\n\n", end - 1, end - minEnd, StringComparison.Ordinal);
            if (paragraph >= minEnd) return paragraph + 2;

            for (var i = end - 1; i >= minEnd; i--)
            {
                var c = text[i];
                if ((c == '.' || c == '!' || c == '?' || c == '\n') && (i + 1 == text.Length || char.IsWhiteSpace(text[i + 1])))
                {
                    return i + 1;
                }
            }

            var space = text.LastIndexOf(' ', end - 1, end - minEnd);
            return space >= minEnd ? space + 1 : end;
        }

        /// <summary>Chuẩn hoá vector về độ dài 1. Vector toàn số 0 trả null: không dùng được để so sánh.</summary>
        public static float[]? UnitVector(float[] vector)
        {
            double sum = 0;
            foreach (var v in vector) sum += v * v;
            if (sum <= 0 || double.IsNaN(sum) || double.IsInfinity(sum)) return null;

            var length = Math.Sqrt(sum);
            var result = new float[vector.Length];
            for (var i = 0; i < vector.Length; i++) result[i] = (float)(vector[i] / length);
            return result;
        }

        public static double Dot(float[] a, float[] b)
        {
            if (a.Length != b.Length) return double.NegativeInfinity;
            double sum = 0;
            for (var i = 0; i < a.Length; i++) sum += a[i] * b[i];
            return sum;
        }
    }

    /// <summary>
    /// Lọc luồng câu trả lời: giữ [n] hợp lệ, bỏ [n] ngoài danh sách nguồn, báo nguồn được nhắc lần đầu.
    /// Một mốc [n] có thể bị cắt giữa hai token nên phần chưa chắc được giữ lại tới token sau.
    /// </summary>
    public sealed class CitationStreamFilter
    {
        private const int MaxMarkerLength = 5;
        private static readonly Regex Marker = new(@"\[(\d{1,3})\]", RegexOptions.Compiled);

        private readonly int _sourceCount;
        private readonly HashSet<int> _cited = new();
        private string _pending = string.Empty;

        public CitationStreamFilter(int sourceCount)
        {
            _sourceCount = sourceCount;
        }

        public IReadOnlyCollection<int> Cited => _cited;

        public (string Text, List<int> NewCitations) Push(string token)
        {
            var text = _pending + token;
            _pending = string.Empty;

            var open = text.LastIndexOf('[');
            if (open >= 0 && text.IndexOf(']', open) < 0 && text.Length - open < MaxMarkerLength
                && IsDigits(text.AsSpan(open + 1)))
            {
                _pending = text.Substring(open);
                text = text.Substring(0, open);
            }

            return Apply(text);
        }

        public (string Text, List<int> NewCitations) Flush()
        {
            var text = _pending;
            _pending = string.Empty;
            return Apply(text);
        }

        private (string Text, List<int> NewCitations) Apply(string text)
        {
            var newCitations = new List<int>();
            var cleaned = Marker.Replace(text, match =>
            {
                var index = int.Parse(match.Groups[1].Value);
                if (index < 1 || index > _sourceCount) return string.Empty;
                if (_cited.Add(index)) newCitations.Add(index);
                return match.Value;
            });
            return (cleaned, newCitations);
        }

        private static bool IsDigits(ReadOnlySpan<char> span)
        {
            foreach (var c in span)
            {
                if (!char.IsDigit(c)) return false;
            }
            return true;
        }
    }
}
