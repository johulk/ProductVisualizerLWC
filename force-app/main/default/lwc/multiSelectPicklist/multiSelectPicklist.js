import { api, LightningElement, track } from 'lwc';

// Multi-select dropdown for filtering products
export default class MultiSelectPicklist extends LightningElement {
    // Component properties
    @api disabled = false;
    @api label = '';
    @api name;
    @api options = [];
    @api placeholder = 'Select an Option';

    // Internal state
    @track currentOptions = [];
    @track selectedItems = [];
    @track selectedOptions = [];
    @track isInitialized = false;
    @track isLoaded = false;
    @track isVisible = false;

    renderedCallback() {
        if (!this.isInitialized) {
            this.initializeEventListeners();
            this.isInitialized = true;
            this.setSelection();
        }
    }

    // Set up click handlers
    initializeEventListeners() {
        const input = this.template.querySelector('.multi-select-combobox__input');
        if (input) {
            input.addEventListener('click', this.handleInputClick.bind(this));
        }

        this.template.addEventListener('click', this.handleTemplateClick.bind(this));
        document.addEventListener('click', this.handleDocumentClick.bind(this));
    }

    // Click handlers
    handleInputClick(event) {
        // Prevent default to avoid any text selection
        event.preventDefault();
        this.handleClick(event.target);
        event.stopPropagation();
    }

    handleTemplateClick(event) {
        event.stopPropagation();
    }

    handleDocumentClick() {
        this.close();
    }

    handleChange(event) {
        this.change(event);
    }

    handleRemove(event) {
        this.selectedOptions.splice(event.detail.index, 1);
        this.change(event);
    }

    handleClick() {
        this.initializeOptions();
        this.toggleDropdown();
    }

    // Core functionality
    initializeOptions() {
        if (!this.isLoaded || this.currentOptions?.length !== this.options?.length) {
            this.currentOptions = JSON.parse(JSON.stringify(this.options));
            this.isLoaded = true;
        }
    }

    toggleDropdown() {
        const dropdown = this.template.querySelector('.slds-is-open');
        if (dropdown) {
            this.close();
        } else {
            this.open();
        }
    }

    open() {
        this.template.querySelectorAll('.multi-select-combobox__dropdown')
            .forEach(node => node.classList.add('slds-is-open'));
    }

    close() {
        this.template.querySelectorAll('.multi-select-combobox__dropdown')
            .forEach(node => node.classList.remove('slds-is-open'));
        this.dispatchEvent(new CustomEvent('close'));
    }

    change(event) {
        if (this.singleSelect) {
            this.resetSelection();
        }

        const changedValue = event.detail.item.value;
        this.updateSelection(changedValue);
        this.setSelection();
        
        this.dispatchSelectionEvent();
    }

    resetSelection() {
        this.currentOptions.forEach(item => item.selected = false);
    }

    updateSelection(changedValue) {
        this.currentOptions.forEach(item => {
            if (item.value === changedValue) {
                item.selected = event.detail.selected;
            }
        });
    }

    setSelection() {
        const selectedItems = this.getSelectedItems();
        let selection = '';
        
        if (selectedItems.length < 1) {
            selection = this.placeholder;
            this.selectedOptions = [];
        } else if (selectedItems.length > 2) {
            selection = `${selectedItems.length} Options Selected`;
            this.selectedOptions = selectedItems;
        } else {
            selection = selectedItems.map(selected => selected.label).join(', ');
            this.selectedOptions = selectedItems;
        }
        
        this.selectedItems = selection;
        this.isVisible = this.selectedOptions?.length > 0;
    }

    dispatchSelectionEvent() {
        const selection = this.getSelectedItems();
        this.dispatchEvent(new CustomEvent('change', { 
            detail: selection 
        }));
    }

    getSelectedItems() {
        return this.currentOptions.filter(item => item.selected);
    }
}