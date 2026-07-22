import { api, LightningElement, track } from "lwc"
import { NavigationMixin } from 'lightning/navigation'
import { subscribe, unsubscribe, onError, setDebugFlag, isEmpEnabled } from 'lightning/empApi'
import { encodeDefaultFieldValues } from 'lightning/pageReferenceUtils'
import Id from '@salesforce/user/Id';
import getEvents from "@salesforce/apex/CustomCalendarHelper.getEvents"
import { formatEvents } from "c/calendarUtils"
export default class CustomCalendar extends NavigationMixin(LightningElement) {
     @api recordId
     @api childObject
     @api parentFieldName
     @api startDatetimeField
     @api endDatetimeField
     @api titleField
     @api channelName

     /* Expose optional field API names so template can render them when provided */
     @api currencyField
     @api assignedToField

     userId = Id

     startDate
     endDate

     // Modal state and prefill values for date click
     @track isModalOpen = false
     prefillStart
     prefillEnd

     connectedCallback() {
          this.addEventListener('fceventclick', this.handleEventClick)
          this.addEventListener('fcdateclick', this.handleDateClick)
          
          if (!!this.channelName) {
               this.handleSubscribe()
          }

          if (!this.recordId) {
               this.recordId = this.userId
          }

          // Hard-default standard Event fields if the consumer didn't pass them
          if (this.childObject === 'Event') {
               if (!this.titleField) this.titleField = 'Subject'
               if (!this.startDatetimeField) this.startDatetimeField = 'StartDateTime'
               if (!this.endDatetimeField) this.endDatetimeField = 'EndDateTime'
               if (!this.assignedToField) this.assignedToField = 'OwnerId'
               // CurrencyIsoCode exists only if multi-currency enabled; safe to set, template is conditional
               if (!this.currencyField) this.currencyField = 'CurrencyIsoCode'
          }
     }
          
     async handleSubscribe() {
          
          const messageCallback = (response) => {
               console.log('New message received: ', JSON.stringify(response))
               console.log('refreshing...')
               this.fetchEvents()
          }
     
          const response = await subscribe(this.channel, -1, messageCallback)
               
          console.log(
               'Subscription request sent to: ',
               JSON.stringify(response.channel)
          )
          this.subscription = response
          
     }    

     get channel() {
          return `/event/${this.channelName}`
     }

     get config() {
          return {
               recordId: this.recordId,
               childObject: this.childObject,
               parentFieldName: this.parentFieldName,
               startDatetimeField: this.startDatetimeField,
               endDatetimeField: this.endDatetimeField,
               titleField: this.titleField,
               startDate: this.startDate,
               endDate: this.endDate
          }
     }

     handleDateChange(event) {
          const { startDate, endDate } = event.detail.value

          this.startDate = startDate
          this.endDate = endDate

          this.fetchEvents()
     }

     handleEventClick = (event) => {
          try {
               const { Id } = event.detail.value.event._def.extendedProps
               console.log(Id)

               
               this[NavigationMixin.Navigate]({
                    type: 'standard__objectPage',
                    attributes: {
                         recordId: Id,
                         objectApiName: this.childObject,
                         actionName: 'edit',
                    }
               })
          } catch (error) {
               console.log(error)
          }
     }

     handleDateClick = (event) => {
          try {
               // Ensure defaults when opened inside a custom tab without attributes
               if (!this.childObject) {
                    this.childObject = 'Event'
               }
               if (this.childObject === 'Event') {
                    if (!this.titleField) this.titleField = 'Subject'
                    if (!this.startDatetimeField) this.startDatetimeField = 'StartDateTime'
                    if (!this.endDatetimeField) this.endDatetimeField = 'EndDateTime'
                    if (!this.assignedToField) this.assignedToField = 'OwnerId'
                    if (!this.currencyField) this.currencyField = 'CurrencyIsoCode'
               }

               // Switch from navigation to in-component modal
               const date = event?.detail?.value?.date
               const iso = date instanceof Date ? date.toISOString() : null
               this.prefillStart = iso
               this.prefillEnd = iso
               this.isModalOpen = true
          } catch (error) {
               console.log(error)
          }    
     }

     async fetchEvents() {
          console.log(this.config)
          const events = formatEvents(await getEvents(this.config), this.config)
          console.log(events)

          // Check if calendar component is available before trying to set events
          const calendarComponent = this.template.querySelector("c-calendar");
          if (calendarComponent) {
              calendarComponent.setEvents(events);
          }
     }

     // Form state for custom create
     formSubject = ''
     formOwnerId = ''
     formCurrency = ''

     get showCurrency() {
          // Render currency input if org likely has multi-currency or currencyField was set
          return this.currencyField === 'CurrencyIsoCode' || !!this.currencyField
     }

     handleInputChange = (evt) => {
          const field = evt.target.dataset.field
          const val = evt.detail && typeof evt.detail.value !== 'undefined' ? evt.detail.value : evt.target.value
          switch (field) {
               case 'subject':
                    this.formSubject = val
                    break
               case 'start':
                    this.prefillStart = val
                    break
               case 'end':
                    this.prefillEnd = val
                    break
               case 'owner':
                    this.formOwnerId = val
                    break
               case 'currency':
                    this.formCurrency = val
                    break
               default:
                    break
          }
     }

     // Modal helpers
     closeModal = () => {
          this.isModalOpen = false
     }

     // Custom save via Apex for Event (UI API not supported)
     handleCustomSave = async () => {
          try {
               // Ensure defaults for Event mode
               if (!this.childObject) this.childObject = 'Event'

               // Basic validation
               if (!this.formSubject) {
                    // eslint-disable-next-line no-console
                    console.warn('Subject is required')
                    return
               }
               if (!this.prefillStart || !this.prefillEnd) {
                    console.warn('Start and End are required')
                    return
               }

               // Build payload
               const payload = {
                    subject: this.formSubject,
                    startIso: this.prefillStart,
                    endIso: this.prefillEnd,
                    ownerId: this.formOwnerId || this.userId,
                    currencyIsoCode: this.showCurrency ? (this.formCurrency || null) : null,
                    parentFieldApiName: this.parentFieldName || null,
                    parentRecordId: this.parentFieldName ? this.recordId : null
               }

               // Call Apex directly (no lazy import due to LWC1503 restriction)
               const result = await CustomCalendarHelper.createEvent(payload);
               console.log('Created Event ID:', result);

               this.isModalOpen = false
               this.fetchEvents()
          } catch (e) {
               // eslint-disable-next-line no-console
               console.error('Create Event failed', e)
          }
     }

     handleCreateSuccess = () => {
          this.isModalOpen = false
          // refresh calendar after create
          this.fetchEvents()
     }

     handleCreateError = () => {
          // keep modal open; lightning-messages will display validation
     }
}