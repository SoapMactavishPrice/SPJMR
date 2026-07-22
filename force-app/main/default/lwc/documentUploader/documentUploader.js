import { LightningElement, api, track } from "lwc";
import getOrCreateDocument from "@salesforce/apex/DocumentUploaderController.getOrCreateDocument";
import deleteFiles from "@salesforce/apex/DocumentUploaderController.deleteFiles";
import getFileSizes from "@salesforce/apex/DocumentUploaderController.getFileSizes";
import uploadFiles from "@salesforce/apex/DocumentUploaderController.uploadFiles";

import { ShowToastEvent } from "lightning/platformShowToastEvent";


export default class DocumentUploader extends LightningElement {

    @api applicationId;
    @api fieldMeta;
    @api sectionName;
    @api disabled;

    @track docId = null;
    @track files = [];
    @track isUploading = false;

    // default properties
    label = "Upload Document";
    accept = ['.pdf', '.png', '.jpg', '.jpeg', '.doc', '.docx', '.xls', '.xlsx', '.ppt', '.pptx'];
    docCode = null;
    maxFiles = 1;
    maxFileSizeMb = 2;

    get allowMultiple() {
        return this.maxFiles > 1 ? true : this.fieldMeta.allowMultiple === true;
    }

    get useCustomUpload() {
        return this.fieldMeta?.uploadEngine === "custom" ||
            this.fieldMeta?.preUploadValidation === true;
    }

    get customUploadStyleLabelClass() {
        return this.fieldMeta?.uploadEngine === "custom" ? 'doc-label-custom' : 'doc-label'
    }

    get acceptString() {
        return Array.isArray(this.accept) ? this.accept.join(",") : this.accept;
    }

    get acceptTitle() {
        return Array.isArray(this.accept) ? this.accept.join(", ") : this.accept;
    }

    get disableUpload() {
        return this.files.length >= this.maxFiles || this.disabled || this.isUploading;
    }

    get showLimitExceeded() {
        return this.files.length >= this.maxFiles;
    }

    get isRequired() {
        return this.fieldMeta.required === true;
    }

    get validationConfig() {
        return this.fieldMeta?.validations || {};
    }

    connectedCallback() {
        this.loadConfig();
        this.init();
    }

    /* ------------------------------------------
       LOAD CONFIG FROM FIELD META
    ------------------------------------------ */
    loadConfig() {
        if (!this.fieldMeta) return;

        this.docCode = this.fieldMeta.docCode;
        this.label = this.fieldMeta.label || this.label;
        this.accept = this.fieldMeta.accept || this.accept;
        this.maxFiles = this.fieldMeta.maxFiles || this.maxFiles;
        this.maxFileSizeMb = this.fieldMeta.maxFileSizeMb || this.maxFileSizeMb;
    }

    /* ------------------------------------------
       INIT: get/create Document_Details__c & fetch files
    ------------------------------------------ */
    async init() {
        try {
            if (!this.applicationId || !this.docCode) {
                console.warn("Missing applicationId or docCode");
                return;
            }

            const resp = await getOrCreateDocument({
                applicationId: this.applicationId,
                docCode: this.docCode
            });

            this.docId = resp.documentId;   // this is Document_Details__c Id
            this.files = resp.files || [];

            this.dispatchEvent(new CustomEvent('docsfetched', {
                detail: {
                    documentId:resp.documentId,
                    files:resp.files,
                    api: this.fieldMeta.api,
                    sectionKey: this.sectionName,
                },
                bubbles: true, composed: true
            }));
        } catch (e) {
            console.error("DocumentUploader init error", e);
        }
    }

    async handleCustomFileChange(event) {
        const selectedFiles = Array.from(event.target.files || []);
        event.target.value = null;

        if (!selectedFiles.length) {
            return;
        }

        const remainingSlots = this.maxFiles - this.files.length;
        if (remainingSlots <= 0) {
            this.showToast("Max Files Reached", `You can upload up to ${this.maxFiles} file${this.maxFiles > 1 ? "s" : ""}.`, "error");
            return;
        }

        if (selectedFiles.length > remainingSlots) {
            this.showToast("Too Many Files", `You can upload only ${remainingSlots} more file${remainingSlots > 1 ? "s" : ""}.`, "error");
            return;
        }

        try {
            this.isUploading = true;
            const preparedFiles = [];

            for (const file of selectedFiles) {
                await this.validateFile(file);
                preparedFiles.push({
                    fileName: file.name,
                    base64Data: await this.readFileAsBase64(file)
                });
            }

            await uploadFiles({
                applicationId: this.applicationId,
                docCode: this.docCode,
                files: preparedFiles
            });

            await this.init();
        } catch (e) {
            const message = this.reduceErrorMessage(e);
            this.showToast("Upload Failed", message, "error");
            console.error("DocumentUploader custom upload error", e);
        } finally {
            this.isUploading = false;
        }
    }

    /* ------------------------------------------
       HANDLE UPLOAD FINISHED
    ------------------------------------------ */
    async handleUploadFinished(event) {

        const maxBytes = (this.maxFileSizeMb || 2) * 1024 * 1024;

        let filesToRemove = [];
        let filesToGetSize = [];
        for (const file of event.detail.files) {
            filesToGetSize.push(file.documentId);
        }
        
        const sizeBytesMap = await getFileSizes({ documentIds:filesToGetSize });

        if(sizeBytesMap && Object.keys(sizeBytesMap).length > 0) {
            for (const [documentId,sizeBytes] of Object.entries(sizeBytesMap)) {           
                if (sizeBytes > maxBytes) {
                    filesToRemove.push(documentId);
                }
            }
        }

        // 🔔 Show message only if something was removed
        if (filesToRemove.length > 0) {
            await deleteFiles({ documentIds: filesToRemove });
            this.dispatchEvent(
                new ShowToastEvent({
                    title: "File Size Exceeded",
                    message: `${filesToRemove.length} file${filesToRemove.length > 1 ? 's were' : ' was'} removed because they exceed ${this.maxFileSizeMb} MB limit.`,
                    variant: "error"
                })
            );
        }

        // Refresh list once at the end
        await this.init();

    }


    /* ------------------------------------------
       DELETE FILE
    ------------------------------------------ */
    async handleRemove(event) {
        if(this.disabled){
            return;
        }
        const documentId = event.currentTarget.dataset.documentId;

        try {
            await deleteFiles({ documentIds: [documentId] });
            await this.init();
        } catch (e) {
            console.error("DocumentUploader remove error", e);
        }
    }

    async validateFile(file) {
        this.validateExtension(file);
        this.validateSize(file);
        await this.validateImage(file);
    }

    validateExtension(file) {
        if (!Array.isArray(this.accept) || !this.accept.length) {
            return;
        }

        const lowerName = (file.name || "").toLowerCase();
        const isAllowed = this.accept.some(ext => lowerName.endsWith(String(ext).toLowerCase()));

        if (!isAllowed) {
            throw new Error(`Unsupported file type. Allowed types: ${this.acceptTitle}`);
        }
    }

    validateSize(file) {
        const maxBytes = (this.maxFileSizeMb || 2) * 1024 * 1024;
        if (file.size > maxBytes) {
            throw new Error(`${file.name} exceeds ${this.maxFileSizeMb} MB limit.`);
        }
    }

    async validateImage(file) {
        const constraints = this.validationConfig;
        const needsImageValidation = constraints?.imageWidth || constraints?.imageHeight || constraints?.ratioWidth || constraints?.ratioHeight;

        if (!needsImageValidation || !file.type?.startsWith("image/")) {
            return;
        }

        const { width, height } = await this.getImageDimensions(file);
        let expectedWidth = null;
        let widthTolerance = 0;
        let minWidth = null;
        let maxWidth = null;
        let widthOk = true;

        if (constraints.imageWidth) {
            expectedWidth = Number(constraints.imageWidth);
            widthTolerance = Number(constraints.widthTolerance ?? 0);
            minWidth = expectedWidth - widthTolerance;
            maxWidth = expectedWidth + widthTolerance;
            widthOk = width >= minWidth && width <= maxWidth;
        }

        let expectedHeight = null;
        let heightTolerance = 0;
        let minHeight = null;
        let maxHeight = null;
        let heightOk = true;

        if (constraints.imageHeight) {
            expectedHeight = Number(constraints.imageHeight);
            heightTolerance = Number(constraints.heightTolerance ?? 0);
            minHeight = expectedHeight - heightTolerance;
            maxHeight = expectedHeight + heightTolerance;
            heightOk = height >= minHeight && height <= maxHeight;
        }

        if (!widthOk || !heightOk) {
            throw new Error(this.getDimensionErrorMessage({
                expectedWidth,
                expectedHeight,
                widthTolerance,
                heightTolerance,
                minWidth,
                maxWidth,
                minHeight,
                maxHeight
            }));
        }

        if (constraints.ratioWidth && constraints.ratioHeight) {
            const expectedRatio = Number(constraints.ratioWidth) / Number(constraints.ratioHeight);
            const actualRatio = width / height;
            const tolerance = Number(constraints.ratioTolerance ?? 0.01);

            if (Math.abs(actualRatio - expectedRatio) > tolerance) {
                throw new Error(
                    `Image proportions should be close to ${constraints.ratioWidth}:${constraints.ratioHeight} (portrait format).`
                );
            }
        }
    }

    getDimensionErrorMessage({
        expectedWidth,
        expectedHeight,
        widthTolerance,
        heightTolerance,
        minWidth,
        maxWidth,
        minHeight,
        maxHeight
    }) {
        if (expectedWidth && expectedHeight) {
            if (widthTolerance > 0 || heightTolerance > 0) {
                return `Image dimensions must be between ${minWidth}-${maxWidth}px wide and ${minHeight}-${maxHeight}px high.`;
            }
            return `Image dimensions must be ${expectedWidth}x${expectedHeight}px.`;
        }

        if (expectedWidth) {
            return widthTolerance > 0
                ? `Image width must be between ${minWidth}-${maxWidth}px.`
                : `Image width must be ${expectedWidth}px.`;
        }

        if (expectedHeight) {
            return heightTolerance > 0
                ? `Image height must be between ${minHeight}-${maxHeight}px.`
                : `Image height must be ${expectedHeight}px.`;
        }

        return "Image dimensions are invalid.";
    }

    getImageDimensions(file) {
        return new Promise((resolve, reject) => {
            const reader = new FileReader();
            reader.onload = () => {
                const image = new Image();
                image.onload = () => resolve({ width: image.width, height: image.height });
                image.onerror = () => reject(new Error(`Unable to read image dimensions for ${file.name}.`));
                image.src = reader.result;
            };
            reader.onerror = () => reject(new Error(`Unable to read ${file.name}.`));
            reader.readAsDataURL(file);
        });
    }

    readFileAsBase64(file) {
        return new Promise((resolve, reject) => {
            const reader = new FileReader();
            reader.onload = () => {
                const result = reader.result || "";
                const parts = String(result).split(",");
                resolve(parts.length > 1 ? parts[1] : parts[0]);
            };
            reader.onerror = () => reject(new Error(`Unable to process ${file.name}.`));
            reader.readAsDataURL(file);
        });
    }

    reduceErrorMessage(error) {
        if (error?.body?.message) {
            return error.body.message;
        }

        if (error?.message) {
            return error.message;
        }

        return "Please try again.";
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant
            })
        );
    }
}