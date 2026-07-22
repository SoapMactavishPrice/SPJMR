import { LightningElement, wire, track, api } from 'lwc';
import getSlots from '@salesforce/apex/SlotSchedulerController.getSlots';
import bookSlot from '@salesforce/apex/SlotSchedulerController.bookSlot';
import getLocations from '@salesforce/apex/SlotSchedulerController.getLocations';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getBookedSlots from '@salesforce/apex/SlotSchedulerController.getBookedSlots';
import ConfirmationModal from 'c/confirmationModal';
import { NavigationMixin } from 'lightning/navigation';
import LightningConfirm from 'lightning/confirm';


export default class SlotScheduler extends NavigationMixin(LightningElement) {
    _programCode;
    noSlots = false
    isBookingInProgress = true
    @api 
    get programCode(){
        return this._programCode;
    }
    set programCode(value){
        this._programCode = value;
        this.fetchLocations();
    }
    
    selectedLocation='';
    slotOptions = []
    selectedSlot='';
    locationOptions  = []
    @track slots = [];
    @api bookingInfo;
    @track groupedSlots = [];
    // 24-hour left scale rows (one per hour, 40px per hour to match CSS)
    hours = Array.from({ length: 24 }, (_, h) => {
        const label = String(h).padStart(2, '0') + ':00';
        const top = `${h * 40}px`; // keep in sync with slot layout (40px per hour)
        return { value: h, label, style: `top:${top};` };
    });

    fetchLocations(){
        getLocations()
            .then((data) => {
                console.log('Data is ',JSON.stringify(data))
                this.locationOptions = data.map((location)=>{
                    return { label: location.LocationName__c, value: location.Id };
                })
            })
            .catch((error)=>{
                console.log('Error here ',error)
            })

           
    }

    displayInfo = {
        primaryField: 'LocationName__c',
        additionalFields: ['Name'],
    };

    matchingInfo = {
        primaryField: { fieldPath: 'LocationName__c' },
        additionalFields: [{ fieldPath: 'Name' }],
    };

    handleSlotChange(event){
        console.log('Selected Slot ',event.detail.value, event.detail.label)
        this.selectedSlot = event.detail.value;
        if(this.selectedSlot && this.selectedLocation){
            this.isBookingInProgress = false;
        }
    }


    handleLocationChange(event) {
        console.log('Selected Location:', event.detail.value);
        this.selectedLocation = event.detail.value;
        
        this.fetchSlots();
    }

    concatSlot(value) {
    if (!value || !value.SlotDate__c || value.SlotStartTime__c == null) {
        return '';
    }

    // ---- Date formatting (Apex Date -> YYYY-MM-DD) ----
    const [year, month, day] = value.SlotDate__c.split('-').map(Number);

    const dateObj = new Date(year, month - 1, day);

    const formattedDate = dateObj.toLocaleDateString('en-GB', {
        day: '2-digit',
        month: 'long',
        year: 'numeric'
    });

    // ---- Time formatting (Apex Time -> milliseconds since midnight) ----
    const base = new Date(1970, 0, 1, 0, 0, 0, 0);
    const timeObj = new Date(base.getTime() + value.SlotStartTime__c);

    const formattedTime = timeObj.toLocaleTimeString('en-US', {
        hour: '2-digit',
        minute: '2-digit',
        hour12: true
    });

    return `${formattedDate} ${formattedTime}`;
}


    fetchSlots() {
        if (!this.programCode || !this.selectedLocation) return;

        getSlots({ programCode: this.programCode, locationId: this.selectedLocation })
            .then((data) => {
                this.noSlots = data.length==0
                console.log('Data is ',JSON.stringify(data))
                // Transform, then compute lanes per day so overlaps are placed side-by-side
                // this.slots = data
                //     .map((slot) => this.transformSlot(slot))
                //     .filter(s => s && s.start && s.end);

                
                // this.groupSlotsByDate();
                // // After grouping by date, compute lane layout for each day column
                // this.groupedSlots = this.groupedSlots.map(day => {
                //     const laidOut = this.computeLanes(day.slots);
                //     return {
                //         ...day,
                //         slots: laidOut.slots,
                //         laneCount: laidOut.laneCount
                //     };
                // });
                const locationMap = new Map();

            data.forEach(slot => {
                if (!locationMap.has(slot.LocationMaster__c)) {
                    locationMap.set(
                        slot.LocationMaster__c,
                        slot.LocationMaster__r?.LocationName__c
                    );
                }
            });

            // this.locationOptions = Array.from(locationMap.entries()).map(
            //     ([value, label]) => ({
            //         label,
            //         value
            //     })
            // );


                this.slotOptions = data.map((slot)=>{
                    return { label: this.concatSlot(slot), value: slot.Id };
                })

                console.log('All Options are ',JSON.stringify(this.locationOptions), JSON.stringify(this.slotOptions))
            })
            .catch((error) => {
                console.error(error);
                this.slots = [];
            });
    }

    checkExistingBookings(){
        console.log('Inside checkExistingBookings ',this.programCode,this.selectedSlot)
        getBookedSlots({pgmCode:this.programCode,slotId:this.selectedSlot})
        .then((result)=>{
            console.log('Inside Existing Bookings', result)
            return result
        })
        .catch((error)=>{
            console.log('Error in fetching Booked Slots ',JSON.stringify(error))
            
        })
    }

   async handleBookSlot(){
        this.isBookingInProgress = true
        this.dispatchEvent(new CustomEvent('bookingprogress'))
        if(this.checkExistingBookings()){
            this.isBookingInProgress = false
            this.showToast('Cannot Book Slot','Slot has already been booked for you','warning')
            return
        }
         const confirmResult = await LightningConfirm.open({
            message: 'Are you sure you want to book this slot?',
            variant: 'headerless',
            label: '',
           
        });
        if(!confirmResult){
            this.isBookingInProgress = false
            return
        }
        console.log('Params are ',this.selectedLocation, this.selectedSlot)
        if(this.programCode && this.selectedSlot){
            bookSlot({programCode:this.programCode,slotId:this.selectedSlot})
            .then((result)=>{
                console.log('Result of Booking is ',JSON.stringify(result))
                if(result == 'Booking successful'){
                    this.showToast('Success','Slot Booked Successfully','success')
                    //   this[NavigationMixin.Navigate]({
                    //         type: 'comm__namedPage',
                    //         attributes: {
                    //             name: 'Home'   // developer name of the page
                    //         },
                            
                    //     });
                    this.dispatchEvent(new CustomEvent('slotselected'))
                    
                }
            })
            .catch((error)=>{
                console.log('Error creating Interview Slot ',JSON.stringify(error))
                this.close('Fail')
            })
        }
    }

    // 2️⃣ Combine SlotDate__c + SlotStartTime__c into JS Date objects
    // transformSlot(slot) {
    //     if (!slot.SlotDate__c) {
    //         console.warn('Missing SlotDate__c for', slot.Id);
    //         return null;
    //     }

    //     // Convert numeric Time (milliseconds since midnight) to a Date (no timezone shift)
    //     // The incoming times represent wall-clock milliseconds since midnight in local time.
    //     // Build a local Date at midnight then add ms to avoid timezone offsets.
    //     const dateParts = slot.SlotDate__c.split('-'); // [YYYY, MM, DD]
    //     const year = parseInt(dateParts[0], 10);
    //     const month = parseInt(dateParts[1], 10) - 1; // JS months = 0–11
    //     const day = parseInt(dateParts[2], 10);

    //     const base = new Date(year, month, day, 0, 0, 0, 0);
    //     const start = typeof slot.SlotStartTime__c === 'number'
    //         ? new Date(base.getTime() + slot.SlotStartTime__c)
    //         : null;
    //     const end = typeof slot.SlotEndtime__c === 'number'
    //         ? new Date(base.getTime() + slot.SlotEndtime__c)
    //         : null;

    //     if (!start || !end || isNaN(start.getTime()) || isNaN(end.getTime())) {
    //         return {
    //             ...slot,
    //             id: slot.Id,
    //             name: slot.Name,
    //             start: null,
    //             end: null,
    //             tooltip: `Invalid Time\nCapacity: ${slot.BookedCapacity__c || 0}/${slot.Capacity__c}`,
    //             cssClass: 'slot invalid',
    //             style: ''
    //         };
    //     }

    //     const durationHours = (end - start) / (1000 * 60 * 60);
    //     const startHour = start.getHours() + start.getMinutes() / 60;

    //     // Vertical layout (40px per hour to match CSS grid)
    //     const top = `${startHour * 40}px`;
    //     const height = `${durationHours * 40}px`;

    //     // Force 24-hour HH:mm in tooltip
    //     const fmt = { hour: '2-digit', minute: '2-digit', hour12: false };
    //     const tooltip = `Time: ${start.toLocaleTimeString('en-GB', fmt)} - ${end.toLocaleTimeString('en-GB', fmt)}
    // Capacity: ${slot.BookedCapacity__c || 0}/${slot.Capacity__c}`;

    //     const cssClass =
    //         slot.BookedCapacity__c >= slot.Capacity__c
    //             ? 'slot full'
    //             : 'slot available';

    //     // left/width will be filled by lane computation later
    //     return {
    //         ...slot,
    //         id: slot.Id,
    //         Name: slot.Name,
    //         name: slot.Name,
    //         start,
    //         end,
    //         tooltip,
    //         cssClass,
    //         topPx: parseFloat(top),
    //         heightPx: parseFloat(height),
    //         lane: 0,
    //         leftPct: 0,
    //         widthPct: 100,
    //         style: `top:${top}; height:${height}; left:0%; width:100%;`
    //     };
    // }


    // 3️⃣ Group by SlotDate__c for the 5-day timeline
    groupSlotsByDate() {
        const map = new Map();
        this.slots.forEach((slot) => {
            const dateKey = slot.start.toISOString().split('T')[0];
            if (!map.has(dateKey)) {
                map.set(dateKey, []);
            }
            map.get(dateKey).push(slot);
        });

        this.groupedSlots = Array.from(map.entries()).map(([date, slots]) => ({
            date,
            dateLabel: new Date(date).toLocaleDateString([], { weekday: 'short', month: 'short', day: 'numeric' }),
            slots
        }));
    }

    // 4️⃣ Visual state
    getSlotCss(slot, start, end) {
        if (!start || !end || end <= start) return 'slot invalid';
        if (slot.BookedCapacity__c >= slot.Capacity__c) return 'slot full';
        return 'slot available';
    }

    // Compute parallel lane layout so overlapping slots are placed side-by-side.
    // Greedy algorithm: assign each interval to the first free lane, track current end time per lane.
    computeLanes(slots) {
        if (!slots || slots.length === 0) {
            return { slots: [], laneCount: 0 };
        }

        // Sort by start time asc, then by end time asc for stability
        const sorted = [...slots].sort((a, b) => {
            if (a.start.getTime() !== b.start.getTime()) {
                return a.start - b.start;
            }
            return a.end - b.end;
        });

        // lanesEnd[i] = end time (ms) of the last slot placed in lane i
        const lanesEnd = [];
        const placed = [];

        sorted.forEach(s => {
            // find first lane whose latest end <= current start (no overlap)
            let laneIndex = -1;
            for (let i = 0; i < lanesEnd.length; i++) {
                if (lanesEnd[i] <= s.start.getTime()) {
                    laneIndex = i;
                    break;
                }
            }
            if (laneIndex === -1) {
                laneIndex = lanesEnd.length;
                lanesEnd.push(s.end.getTime());
            } else {
                lanesEnd[laneIndex] = s.end.getTime();
            }

            const laneCount = Math.max(lanesEnd.length, 1);
            const gutterPct = 2; // small gutter between lanes
            const totalGutters = (laneCount - 1) * gutterPct;
            const baseWidth = (100 - totalGutters) / laneCount;
            const left = laneIndex * (baseWidth + gutterPct);
            const width = baseWidth;

            // Build style using already computed vertical metrics
            const style = `top:${s.topPx}px; height:${s.heightPx}px; left:${left}%; width:${width}%;`;

            placed.push({
                ...s,
                lane: laneIndex,
                laneCount,
                leftPct: left,
                widthPct: width,
                style
            });
        });

        // Important: width should reflect max concurrent overlap.
        // Recalculate with final laneCount = max lanes used at any time.
        const finalLaneCount = lanesEnd.length;
        const finalGutter = 2;
        const finalTotalGutters = (finalLaneCount - 1) * finalGutter;
        const finalBaseWidth = (finalLaneCount > 0) ? (100 - finalTotalGutters) / finalLaneCount : 100;

        const normalized = placed.map(p => {
            const left = p.lane * (finalBaseWidth + finalGutter);
            const width = finalBaseWidth;
            return {
                ...p,
                laneCount: finalLaneCount,
                leftPct: left,
                widthPct: width,
                style: `top:${p.topPx}px; height:${p.heightPx}px; left:${left}%; width:${width}%;`
            };
        });

        return { slots: normalized, laneCount: finalLaneCount };
    }

    findSlotById(slotId) {
    for (let day of this.groupedSlots) {
        for (let slot of day.slots) {
            if (slot.id === slotId) {
                return slot;
            }
        }
    }
    return null;
}


    async confirmSlotSelection(event) {
    const slotId = event.currentTarget.dataset.id;
    if (!slotId) return;

    // 🔍 Find the clicked slot object
    const clickedSlot = this.findSlotById(slotId);

    console.log("CURRENT BOOKING INFO: ", JSON.stringify(this.bookingInfo));
    console.log("CLICKED SLOT: ", clickedSlot);

    // If user has an existing booking → compare
    if (this.bookingInfo && clickedSlot) {

        // Convert bookingInfo time strings ("12:00 AM") to 24-hour "HH:mm"
        const formatTime = (t) =>
            new Date(`1970-01-01 ${t}`).toLocaleTimeString("en-GB", {
                hour: "2-digit",
                minute: "2-digit",
                hour12: false
            });

        const bookedStart = formatTime(this.bookingInfo.bookingStartTime);
        const bookedEnd = formatTime(this.bookingInfo.bookingEndTime);
        console.log(bookedEnd, bookedStart)
        // Get clicked slot times as 24-hour HH:mm
        const clickedStart = clickedSlot.start.toLocaleTimeString("en-GB", {
            hour: "2-digit",
            minute: "2-digit",
            hour12: false
        });

        const clickedEnd = clickedSlot.end.toLocaleTimeString("en-GB", {
            hour: "2-digit",
            minute: "2-digit",
            hour12: false
        });

        const clickedDate = clickedSlot.start.toISOString().split("T")[0];
        console.log('Clicked Date ',clickedDate, ' ',this.bookingInfo.bookingDate ,
            clickedStart, '  ',bookedStart,'   ',clickedEnd,'   ',bookedEnd 
        )
        // 🔥 DUPLICATE CHECK → Same date + matching start + matching end
        if (
            clickedDate === this.bookingInfo.bookingDate &&
            clickedStart === bookedStart &&
            clickedEnd === bookedEnd
        ) {
            this.showToast(
                "Already Booked",
                "You have already booked this slot.",
                "warning"
            );
            return; // ❌ Stop further flow
        }
    }

    // 🟢 If not duplicate, show confirmation modal
    const result = await ConfirmationModal.open({
        size: "small",
        description: "Confirm your action",
        message: "The selected slot will be booked for you",
        headerLabel: "Schedule Interview"
    });

    if (result === "confirm") {
        this.handleSlotSelection(slotId, this.programCode, this.bookingInfo);
    }
}


    // 5️⃣ Handle booking click
    // handleSlotSelection(slotId, programCode, bookingInfo) {
    //     const bookingInfoStr = bookingInfo ? JSON.stringify(bookingInfo) : null;
    //     bookSlot({slotId: slotId,programCode: programCode,bookingInfo:bookingInfoStr })
    //         .then((msg) => {
    //             console.log('Slot booked:', msg);
    //             this.showToast('Success', msg, 'success');
    //             this.fetchSlots();
    //             console.log('slotselected event before');
    //             this.dispatchEvent(new CustomEvent('slotselected', { detail: { slotId } }));
    //             console.log('slotselected event before');
    //         })
    //         .catch((error) => {
    //             console.error(error);
    //             this.showToast('Error', error.body.message, 'error');
    //         });
    // }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}