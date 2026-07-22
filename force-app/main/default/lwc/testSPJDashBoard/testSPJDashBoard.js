import { LightningElement, track, api } from 'lwc';
import getUserInfo from '@salesforce/apex/StudentProfileDashboardController.getUserInfo';
import logo from '@salesforce/resourceUrl/Site_Logo';
// import studentService from '@salesforce/resourceUrl/Student_Service';
// Import static resources for menu icons
import programDetailsIcon from '@salesforce/resourceUrl/Program_Details';
import financeIcon from '@salesforce/resourceUrl/Finance_Icon';
import mentorIcon from '@salesforce/resourceUrl/Mentor_Icon';
import projectIcon from '@salesforce/resourceUrl/Project_Icon';
import ticketIcon from '@salesforce/resourceUrl/Ticket_Icon';
import studentDetailsIcon from '@salesforce/resourceUrl/Student_Details';
import navbarIcon from '@salesforce/resourceUrl/Navbar_Icon';
import profileDummy from '@salesforce/resourceUrl/Profile_Dummy';
// Import static resources for the 7 menu items that currently use Lightning icons
import attendanceIcon from '@salesforce/resourceUrl/Attendance_Icon';
import examsIcon from '@salesforce/resourceUrl/Exams_Icon';
import academicsIcon from '@salesforce/resourceUrl/Academics_Icon';
import servicesIcon from '@salesforce/resourceUrl/Services_Icon';
import hostelIcon from '@salesforce/resourceUrl/Hostel_Icon';
import logoutIcon from '@salesforce/resourceUrl/Logout_Icon';

export default class Spjimr_studentProfileDashboard extends LightningElement {
    // Navigation state
     @track selectedMenuItem = 'studentDetails';
    @track isSidebarOpen = true; // Sidebar open by default
    siteLogoIcon = logo;
    navbarIcon = navbarIcon;
    profileDummyIcon = profileDummy;

    programDetailsIconResource = programDetailsIcon;
    financeIconResource = financeIcon;
    mentorIconResource = mentorIcon;
    projectIconResource = projectIcon;
    ticketIconResource = ticketIcon;
    studentDetailsIconResource = studentDetailsIcon;
    // Static resource icons for the 7 menu items
    attendanceIconResource = attendanceIcon;
    examsIconResource = examsIcon;
    academicsIconResource = academicsIcon;
    servicesIconResource = servicesIcon;
    hostelIconResource = hostelIcon;
    logoutIconResource = logoutIcon;
    @api siteLogo;
    @api menuIcon;
    @api ticketIcon;
    @api projectIcon;
    @api mentorIcon;
    @api financeIcon;
    @api programDetailsIcon;
    @api studentDetailsIcon;
    @api attendanceIcon;
    @api examsIcon;
    @api academicsIcon;
    @api servicesIcon;
    @api hostelIcon;
    @api reportsIcon;
    @api logoutIcon;  
    @track preQua  

    // Student Information
    @track studentName = 'John Steve';
    @track studentEmail = '';
    @track rollNumber = '';
    @track programName = '';
    @track programCode = '';
    @track batchName = '';
    @track studentGender = '';
    @track currentTerm = 'Term 2';
    @track status = 'Accepted';
    @track credits = '372';
    @track points = '41';
    @track prevQualification='';
    @track graduationYear ='';
    @track marks = '';
    @track term = '';
    @track address = '';
    @track isEmergencyModalOpen = false;
   
    
    
    // Profile Image - Replace with actual image URL
    @track profileImage = 'data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHdpZHRoPSIxMDAiIGhlaWdodD0iMTAwIiB2aWV3Qm94PSIwIDAgMTAwIDEwMCI+PHJlY3Qgd2lkdGg9IjEwMCIgaGVpZ2h0PSIxMDAiIGZpbGw9IiNjY2MiLz48dGV4dCB4PSI1MCIgeT0iNTAiIGZvbnQtZmFtaWx5PSJBcmlhbCIgZm9udC1zaXplPSIxNCIgZmlsbD0iI2ZmZiIgdGV4dC1hbmNob3I9Im1pZGRsZSIgZHk9Ii4zZW0iPlByb2ZpbGU8L3RleHQ+PC9zdmc+';
    
    // Personal Details
    @track dateOfBirth = '';
    @track gender = 'Male';
    
    // Contact Info
    @track mobileNumber = '';
    @track email = 'John@gmail.com';
    // @track address = 'Plot no 20, johny street, Bengaluru, Karnataka - 600811';
    
    // Academic Background
    
    
    // Fees Section
    @track applicationFee = '₹1,000';
    @track paymentStatus = 'Pending';
    @track dueDate = '12/03/2025';
    
    // Navigation menu items - all using static resources now
    // @track menuItems = [
    //     { id: 'studentDetails', label: 'Student Details', icon: 'utility:grid', iconType: 'static', isSelected: true, cssClass: 'nav-item selected' },
    //     { id: 'programDetails', label: 'Program details', icon: 'utility:folder', iconType: 'static', isSelected: false, cssClass: 'nav-item' },
    //     { id: 'attendance', label: 'Attendance & Schedule', icon: 'utility:user', iconType: 'static', isSelected: false, cssClass: 'nav-item' },
    //     { id: 'exams', label: 'Exams & Evaluation', icon: 'utility:chat', iconType: 'static', isSelected: false, cssClass: 'nav-item' },
    //     { id: 'academics', label: 'Academics & Learning', icon: 'utility:message', iconType: 'static', isSelected: false, cssClass: 'nav-item' },
    //     { id: 'finance', label: 'Finance & Ledger', icon: 'utility:money', iconType: 'static', isSelected: false, cssClass: 'nav-item' },
    //     { id: 'services', label: 'Student Services', icon: 'utility:list', iconType: 'static', isSelected: false, cssClass: 'nav-item' },
    //     { id: 'mentorship', label: 'Mentorship & MQR', icon: 'utility:connected_apps', iconType: 'static', isSelected: false, cssClass: 'nav-item' },
    //     { id: 'hostel', label: 'Hostel & Campus Logistics', icon: 'utility:location', iconType: 'static', isSelected: false, cssClass: 'nav-item' },
    //     { id: 'reports', label: 'Reports & Certificates', icon: 'utility:upload', iconType: 'static', isSelected: false, cssClass: 'nav-item' },
    //     { id: 'project', label: 'Project & Capstone', icon: 'utility:connected_apps', iconType: 'static', isSelected: false, cssClass: 'nav-item' },
    //     { id: 'tickets', label: 'Ticket management', icon: 'utility:ticket', iconType: 'static', isSelected: false, cssClass: 'nav-item' },
    //     { id: 'logout', label: 'Logout', icon: 'utility:logout', iconType: 'static', isSelected: false, cssClass: 'nav-item' }
    // ];

   
     @track isVisible = false;

    showTooltip() {
        this.isVisible = true;
    }

    hideTooltip() {
        this.isVisible = false;
    }
    
    get menuItemsWithIcons() {
        return this.menuItems.map(item => {
            let iconUrl = null;
            
            // Map all menu items to their static resources
            switch(item.id) {
                case 'studentDetails':
                    iconUrl = this.studentDetailsIconResource;
                    break;
                case 'programDetails':
                    iconUrl = this.programDetailsIconResource;
                    break;
                case 'attendance':
                    iconUrl = this.attendanceIconResource;
                    break;
                case 'exams':
                    iconUrl = this.examsIconResource;
                    break;
                case 'academics':
                    iconUrl = this.academicsIconResource;
                    break;
                case 'finance':
                    iconUrl = this.financeIconResource;
                    break;
                case 'services':
                    iconUrl = this.servicesIconResource;
                    break;
                case 'mentorship':
                    iconUrl = this.mentorIconResource;
                    break;
                case 'hostel':
                    iconUrl = this.hostelIconResource;
                    break;
                case 'reports':
                    iconUrl = this.logoutIconResource;
                    break;
                case 'project':
                    iconUrl = this.projectIconResource;
                    break;
                case 'tickets':
                    iconUrl = this.ticketIconResource;
                    break;
                case 'logout':
                    iconUrl = this.logoutIconResource;
                    break;
                default:
                    iconUrl = null;
            }
            
            return {
                ...item,
                iconUrl: iconUrl
            };
        });
    }

    // Handle image error - log error and hide broken image
    handleImageError(event) {
        const img = event.target;
        const imageUrl = img.src;
        console.error('Failed to load CMS image:', imageUrl);
        // Hide the broken image
        img.style.display = 'none';
        // Note: CMS images require proper configuration for guest users
        // See CMS_GUEST_ACCESS_SETUP.md for configuration steps
    }
    
    // Handle menu item click
    handleMenuClick(event) {
        const menuId = event.currentTarget.dataset.id;
        if (menuId === 'logout') {
            this.handleLogout();
        } else {
            this.selectedMenuItem = menuId;
            // Update selected state and CSS class
            this.menuItems = this.menuItems.map(item => ({
                ...item,
                isSelected: item.id === menuId,
                cssClass: item.id === menuId ? 'nav-item selected' : 'nav-item'
            }));
        }
    }
     // Event Handlers
    handleEmergencyContact() {
        this.isEmergencyModalOpen = true;
    }
    
    closeEmergencyModal() {
        // Close Emergency Contact modal
        this.isEmergencyModalOpen = false;
    }
    
    handleLogout() {
        console.log('Logout clicked');
        // Clear browser cache/sessionStorage
        sessionStorage.clear();
        localStorage.clear();
        
        // Use community-specific logout path and URL encode the redirect URL
        const redirectUrl = encodeURIComponent('/student/login?');
        window.location.replace(`/student/secur/logout.jsp?retURL=${redirectUrl}`);
    }
 
    
    handleDownloadCertificate(event) {
        event.preventDefault();
        // Handle certificate download
        console.log('Download Certificate clicked');
        // Add your logic here
    }
    
    handleUploadDocuments() {
        // Handle upload documents button click
        console.log('Upload Documents clicked');
        // Add your logic here
    }
    
    handlePayAcademicFee() {
        // Handle pay academic fee button click
        console.log('Pay Academic Fee clicked');
        // Add your logic here
    }
    
    handleChangeSpecialization() {
        // Handle change of specialization button click
        console.log('Change of Specialization clicked');
        // Add your logic here
    }
    
    // Toggle sidebar visibility
    handleToggleSidebar() {
        this.isSidebarOpen = !this.isSidebarOpen;
    }
    
    // Computed property for sidebar class
    get sidebarClass() {
        return this.isSidebarOpen ? 'sidebar sidebar-open' : 'sidebar sidebar-closed';
    }
    
    // Computed property for main content class
    get mainContentClass() {
        return this.isSidebarOpen ? 'main-content main-content-with-sidebar' : 'main-content main-content-full';
    }

    get isStudentDetailsSection() {
        return this.selectedMenuItem === 'studentDetails';
    }

    get isAttendanceSection() {
        return this.selectedMenuItem === 'attendance';
    }

    // Fetch current user's name when component loads
    connectedCallback() {
        console.log('connectcallback of dashboard');
        this.loadUserName();
    }

    // Load user info (name, email, gender) from Apex
    loadUserName() {
        getUserInfo()
            .then(result => {
                if (result) {
                    console.log('result::',result);
                    this.studentName = result.fullName ;
                    this.studentEmail = result.email || '';
                    this.studentGender = result.gender || '';   
                    this.dateOfBirth = result.dateOfBirth ;
                    this.rollNumber = result.rollNumber || '';
                    this.programName = result.programName || '';
                    this.programCode = result.programCode || '';
                    this.batchName = result.batchName || '';
                    this.mobileNumber = result.mobileNumber || '';
                    this.prevQualification = result.prevQualification || '';
                    this.graduationYear = result.graduationYear || '';
                    this.marks = result.marks || '';
                    this.term = result.term || '';
                    this.address = result.address || '';
                    
                }            
            })
            .catch(error => {
                console.error('Error fetching user info:', error);
                // Keep default values if error occurs
            });
    }
    
}