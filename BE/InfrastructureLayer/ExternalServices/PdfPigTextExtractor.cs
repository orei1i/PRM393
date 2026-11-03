using System;
using System.IO;
using System.Text;
using DomainLayer.Exceptions;
using DomainLayer.Interfaces;
using UglyToad.PdfPig;
using UglyToad.PdfPig.DocumentLayoutAnalysis.TextExtractor;

namespace InfrastructureLayer.ExternalServices
{
    /// <summary>Đọc chữ PDF bằng PdfPig. PDF chỉ có ảnh quét trả chuỗi rỗng, service sẽ báo empty_document.</summary>
    public class PdfPigTextExtractor : IDocumentTextExtractor
    {
        private const int MaxPages = 1000;

        public string ExtractPdf(Stream pdf)
        {
            try
            {
                using var document = PdfDocument.Open(pdf);
                if (document.NumberOfPages > MaxPages)
                {
                    throw new PayloadTooLargeException($"Tài liệu quá dài: tối đa {MaxPages} trang.");
                }

                var text = new StringBuilder();
                foreach (var page in document.GetPages())
                {
                    text.AppendLine(ContentOrderTextExtractor.GetText(page));
                    text.AppendLine();
                }
                return text.ToString();
            }
            catch (DomainException)
            {
                throw;
            }
            catch (Exception ex) when (ex is not OutOfMemoryException)
            {
                // Tệp hỏng hoặc có mật khẩu: PdfPig ném nhiều kiểu khác nhau, đều là lỗi của tệp.
                throw new BadRequestException("Không đọc được tệp PDF này. Tệp có thể bị hỏng hoặc có mật khẩu.", "unreadable_pdf");
            }
        }
    }
}
