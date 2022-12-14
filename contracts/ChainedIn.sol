// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.8;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

error ChainedIn__UserExists();
error ChainedIn__AuthenticationFailed();
error ChainedIn__Unauthorized();
error ChainedIn__UnauthorizedApprover();
error ChainedIn__MustBeCompany();
error ChainedIn__EmployeeNotInCompany();
error ChainedIn__EmployeeAlreadyManager();
error ChainedIn__ExperienceNotForUser();
error ChainedIn__UnknownCompany();
error ChainedIn__SelfEndorsement();

contract ChainedIn is Initializable {
    Company[] public companies;
    User[] public employees;
    Certificate[] public certifications;
    Endorsement[] public endorsements;
    Skill[] public skills;
    Experience[] public experiences;

    mapping(string => address) private emailToAddress;
    mapping(address => uint256) private addressToId;
    mapping(address => bool) private isCompany;

    modifier verifiedUser(uint256 userId) {
        if (userId != addressToId[msg.sender]) {
            revert ChainedIn__Unauthorized();
        }
        _;
    }

    struct Company {
        uint256 id;
        string name;
        address walletAddress;
        uint256[] currentEmployees;
        uint256[] previousEmployees;
        uint256[] unverifiedEmployees;
    }

    struct User {
        uint256 id;
        uint256 companyId;
        uint256 currentActiveExperience;
        string name;
        address walletAddress;
        bool isManager;
        uint256[] skills;
        uint256[] experiences;
    }

    struct Experience {
        string startingDate;
        string endingDate;
        string role;
        bool isActive;
        bool isApproved;
        uint256 companyId;
    }

    struct Certificate {
        uint256 id;
        string url;
        string issuedOn;
        string validTill;
        string name;
        string issuer;
    }

    struct Endorsement {
        uint256 endorserId;
        string date;
        string comment;
    }

    struct Skill {
        uint256 id;
        string name;
        bool isVerified;
        uint256[] certifications;
        uint256[] endorsements;
    }

    enum AccountType {
        UserAccount,
        CompanyAccount
    }

    function initialize() public initializer {
        employees.push();
        companies.push();
        experiences.push();
        certifications.push();
        endorsements.push();
        skills.push();
    }

    function signUp(
        string calldata email,
        string calldata name,
        AccountType accountType
    ) external {
        if (emailToAddress[email] != address(0) || addressToId[msg.sender] != 0) {
            revert ChainedIn__UserExists();
        }

        emailToAddress[email] = msg.sender;

        if (accountType == AccountType.UserAccount) {
            User storage user = employees.push();
            user.name = name;
            user.id = employees.length - 1;
            user.walletAddress = msg.sender;
            addressToId[msg.sender] = user.id;
            user.skills = new uint256[](0);
            user.experiences = new uint256[](0);
        } else {
            Company storage company = companies.push();
            company.name = name;
            company.id = companies.length - 1;
            company.walletAddress = msg.sender;
            company.currentEmployees = new uint256[](0);
            company.previousEmployees = new uint256[](0);
            company.unverifiedEmployees = new uint256[](0);
            addressToId[msg.sender] = company.id;
            isCompany[msg.sender] = true;
        }
    }

    function login(string calldata email)
        external
        view
        returns (AccountType accountType, uint256 userId)
    {
        if (msg.sender != emailToAddress[email]) {
            revert ChainedIn__AuthenticationFailed();
        }

        accountType = isCompany[msg.sender] ? AccountType.CompanyAccount : AccountType.UserAccount;
        userId = addressToId[msg.sender];
    }

    function updateWalletAddress(
        AccountType accountType,
        string calldata email,
        address newAddress
    ) external {
        if (msg.sender != emailToAddress[email]) {
            revert ChainedIn__AuthenticationFailed();
        }

        emailToAddress[email] = newAddress;
        uint256 id = addressToId[msg.sender];
        addressToId[msg.sender] = 0;
        addressToId[newAddress] = id;

        if (accountType == AccountType.UserAccount) {
            employees[id].walletAddress = newAddress;
        } else {
            companies[id].walletAddress = newAddress;
        }
    }

    function addExperience(
        uint256 userId,
        string calldata startingDate,
        string calldata endingDate,
        string calldata role,
        uint256 companyId
    ) external verifiedUser(userId) {
        if (companyId >= companies.length) {
            revert ChainedIn__UnknownCompany();
        }

        Experience storage experience = experiences.push();
        experience.companyId = companyId;
        experience.isActive = false;
        experience.isApproved = false;
        experience.startingDate = startingDate;
        experience.role = role;
        experience.endingDate = endingDate;
        employees[userId].experiences.push(experiences.length - 1);
        companies[companyId].unverifiedEmployees.push(experiences.length - 1);
    }

    function approveExperience(
        uint256 experienceId,
        uint256 companyId,
        bool isActive
    ) external {
        if (
            !((isCompany[msg.sender] &&
                companies[addressToId[msg.sender]].id == experiences[experienceId].companyId) ||
                (employees[addressToId[msg.sender]].isManager &&
                    employees[addressToId[msg.sender]].companyId ==
                    experiences[experienceId].companyId))
        ) {
            revert ChainedIn__UnauthorizedApprover();
        }

        uint256 i;
        experiences[experienceId].isApproved = true;
        experiences[experienceId].isActive = isActive;

        // remove this experience from the unverified list
        for (i = 0; i < companies[companyId].unverifiedEmployees.length; i++) {
            if (companies[companyId].unverifiedEmployees[i] == experienceId) {
                companies[companyId].unverifiedEmployees[i] = 0;
                break;
            }
        }

        if (isActive) {
            // look for any unused slot for the experience
            for (i = 0; i < companies[companyId].currentEmployees.length; i++) {
                if (companies[companyId].currentEmployees[i] == 0) {
                    companies[companyId].currentEmployees[i] = experienceId;
                    break;
                }
            }

            // at this point, if no unused spot was found, we insert a new record
            if (i == companies[companyId].currentEmployees.length) {
                companies[companyId].currentEmployees.push(experienceId);
            }
        } else {
            // look for any unused slot for the experience
            for (i = 0; i < companies[companyId].previousEmployees.length; i++) {
                if (companies[companyId].previousEmployees[i] == 0) {
                    companies[companyId].previousEmployees[i] = experienceId;
                    break;
                }
            }

            // at this point, if no unused spot was found, we insert a new record
            if (i == companies[companyId].currentEmployees.length) {
                companies[companyId].previousEmployees.push(experienceId);
            }
        }
    }

    function setCurrentActiveExperience(uint256 userId, uint256 experienceId)
        external
        verifiedUser(userId)
    {
        // Make sure this experience belongs to this user
        uint256 i;
        for (i = 0; i < employees[userId].experiences.length; i++) {
            if (employees[userId].experiences[i] == experienceId) break;
        }
        if (i == employees[userId].experiences.length) {
            revert ChainedIn__ExperienceNotForUser();
        }

        employees[userId].currentActiveExperience = experienceId;
    }

    function setCompany(uint256 userId, uint256 companyId) external verifiedUser(userId) {
        if (companyId >= companies.length) {
            revert ChainedIn__UnknownCompany();
        }

        employees[userId].companyId = companyId;
    }

    function approveManager(uint256 employeeId) external {
        if (!isCompany[msg.sender]) {
            revert ChainedIn__MustBeCompany();
        }
        if (!(employees[employeeId].companyId == addressToId[msg.sender])) {
            revert ChainedIn__EmployeeNotInCompany();
        }
        if (employees[employeeId].isManager) {
            revert ChainedIn__EmployeeAlreadyManager();
        }

        employees[employeeId].isManager = true;
    }

    function addSkill(uint256 userId, string calldata skillName) external verifiedUser(userId) {
        Skill storage skill = skills.push();
        employees[userId].skills.push(skills.length - 1);
        skill.name = skillName;
        skill.isVerified = false;
        skill.certifications = new uint256[](0);
        skill.endorsements = new uint256[](0);
    }

    function addCertification(
        uint256 userId,
        string calldata url,
        string memory issuedOn,
        string memory validTill,
        string calldata name,
        string calldata issuer,
        uint256 skillId
    ) external verifiedUser(userId) {
        Certificate storage certificate = certifications.push();
        certificate.url = url;
        certificate.issuedOn = issuedOn;
        certificate.validTill = validTill;
        certificate.name = name;
        certificate.id = certifications.length - 1;
        certificate.issuer = issuer;
        skills[skillId].certifications.push(certificate.id);
    }

    function endorseSkill(
        uint256 userId,
        uint256 endorseeId,
        uint256 skillId,
        string calldata date,
        string calldata comment
    ) external verifiedUser(userId) {
        if (userId == endorseeId) {
            revert ChainedIn__SelfEndorsement();
        }

        Endorsement storage endorsement = endorsements.push();
        endorsement.endorserId = userId;
        endorsement.comment = comment;
        endorsement.date = date;
        skills[skillId].endorsements.push(endorsements.length - 1);

        if (employees[userId].isManager) {
            if (employees[userId].companyId == employees[endorseeId].companyId) {
                skills[skillId].isVerified = true;
            }
        }
    }

    function getCompaniesCount() external view returns (uint256) {
        return companies.length;
    }

    function getCompanies() external view returns (Company[] memory) {
        return companies;
    }

    function getEmployeesCount() external view returns (uint256) {
        return employees.length;
    }

    function getEmployees() external view returns (User[] memory) {
        return employees;
    }

    function getCompanyCurrentEmployees(uint256 companyId)
        external
        view
        returns (uint256[] memory)
    {
        return companies[companyId].currentEmployees;
    }

    function getCompanyPreviousEmployees(uint256 companyId)
        external
        view
        returns (uint256[] memory)
    {
        return companies[companyId].previousEmployees;
    }

    function getCompanyUnverifiedEmployees(uint256 companyId)
        external
        view
        returns (uint256[] memory)
    {
        return companies[companyId].unverifiedEmployees;
    }

    function getEmployeeSkills(uint256 userId) external view returns (uint256[] memory) {
        return employees[userId].skills;
    }

    function getEmployeeExperiences(uint256 userId) external view returns (uint256[] memory) {
        return employees[userId].experiences;
    }

    function getSkillCertifications(uint256 skillId) external view returns (uint256[] memory) {
        return skills[skillId].certifications;
    }

    function getSkillEndorsements(uint256 skillId) external view returns (uint256[] memory) {
        return skills[skillId].endorsements;
    }
}
