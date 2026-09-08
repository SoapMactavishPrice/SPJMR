import getDocumentMetadata from '@salesforce/apex/FinalPdfFileFetcher.getDocumentMetadata';
import getPdfChunk from '@salesforce/apex/FinalPdfFileFetcher.getPdfChunk';
import getVfPdfBase64 from '@salesforce/apex/VfPdfFetcher.getVfPdfBase64';

export async function generatePdf({
    recordId,
    PDFDocument,
    LibPDF,
    includeApplicationForm = true,
    includeDocuments = true
}) {
    const mergedPdf = await PDFDocument.create();

    // ==============================
    // Application Form
    // ==============================

    if (includeApplicationForm) {

        const vfBase64 = await getVfPdfBase64({
            recordId
        });

        if (!vfBase64) {
            throw new Error('Application form PDF returned empty data.');
        }

        const vfBytes = Uint8Array.from(
            atob(vfBase64),
            c => c.charCodeAt(0)
        );

        const vfPdf = await PDFDocument.load(vfBytes);

        const pages = await mergedPdf.copyPages(
            vfPdf,
            vfPdf.getPageIndices()
        );

        pages.forEach(page => {
            mergedPdf.addPage(page);
        });
    }

    // ==============================
    // Documents
    // ==============================

    if (includeDocuments) {

        const metadata = await getDocumentMetadata({
            recordId
        });

        const MAX_CHUNK_SIZE = 5000000;

        const chunks = [];
        let currentChunk = [];
        let currentSize = 0;

        for (const file of metadata) {

            if (
                currentChunk.length > 0 &&
                currentSize + file.contentSize > MAX_CHUNK_SIZE
            ) {
                chunks.push(currentChunk);
                currentChunk = [];
                currentSize = 0;
            }

            currentChunk.push(file);
            currentSize += file.contentSize;
        }

        if (currentChunk.length > 0) {
            chunks.push(currentChunk);
        }

        for (const chunk of chunks) {

            const versionIds = chunk.map(
                file => file.versionId
            );

            const pdfFiles = await getPdfChunk({
                versionIds
            });

            for (const pdfFile of pdfFiles) {

                if (!pdfFile.base64Data) {
                    continue;
                }

                const bytes = Uint8Array.from(
                    atob(pdfFile.base64Data),
                    c => c.charCodeAt(0)
                );

                let pdf;

                try {
                    // Fast path: normal, unencrypted PDF
                    pdf = await PDFDocument.load(bytes);

                } catch (pdfLibError) {

                    try {
                        // ==========================================
                        // FALLBACK: restricted/encrypted PDF
                        // ==========================================

                        const sourcePdf = await LibPDF.load(bytes);

                        if (!sourcePdf.isEncrypted) {
                            // pdf-lib failed for some other reason.
                            // Do not silently hide a corrupt/unsupported PDF.
                            throw pdfLibError;
                        }

                        console.log(
                            'Encrypted/restricted PDF detected:',
                            pdfFile.fileName
                        );

                        const cleanPdf = LibPDF.create();

                        const pageIndices = Array.from(
                            { length: sourcePdf.getPageCount() },
                            (_, index) => index
                        );

                        // copyPagesFrom() already inserts the pages.
                        await cleanPdf.copyPagesFrom(
                            sourcePdf,
                            pageIndices
                        );

                        const mergeBytes = await cleanPdf.save();

                        // Verify/load reconstructed PDF using pdf-lib.
                        pdf = await PDFDocument.load(mergeBytes);

                    } catch (libPdfError) {

                        // ==========================================
                        // PASSWORD-PROTECTED / UNSUPPORTED PDF
                        // ==========================================

                        console.warn(
                            'Skipping protected/unsupported PDF:',
                            pdfFile.fileName,
                            pdfFile.versionId,
                            libPdfError
                        );

                        continue;
                    }
                }

                const pages = await mergedPdf.copyPages(
                    pdf,
                    pdf.getPageIndices()
                );

                pages.forEach(page => {
                    mergedPdf.addPage(page);
                });
            }
        }
    }

    return mergedPdf.save();
}