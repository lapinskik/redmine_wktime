class WkcontactController < WkcrmController
  unloadable
  include WkcustomfieldsHelper
  include WkcrmcontactHelper
  include WkcontactHelper
	helper_method :sort_column, :sort_direction

	def index
		set_filter_session
		contactName = session[controller_name][:contactname]
		accountId =  session[controller_name][:account_id]
		locationId = session[controller_name][:location_id]
		wkcontact = nil
		if !contactName.blank? &&  !accountId.blank?
			if accountId == 'AA'
				wkcontact = WkCrmContact.includes(:lead).where(:contact_type => getContactType, wk_leads: { status: ['C', nil] }).where.not(:account_id => nil).where("LOWER(wk_crm_contacts.first_name) like LOWER(?) OR LOWER(wk_crm_contacts.last_name) like LOWER(?)", "%#{contactName}%", "%#{contactName}%")
      elsif accountId == 'EV'
        wkcontact = WkCrmContact.includes(:lead).where(:contact_type => getContactType, wk_leads: { status: ['C', nil] }).where("LOWER(wk_crm_contacts.first_name) like LOWER(?) OR LOWER(wk_crm_contacts.last_name) like LOWER(?)", "%#{contactName}%", "%#{contactName}%")
      else
				wkcontact = WkCrmContact.includes(:lead).where(:contact_type => getContactType, wk_leads: { status: ['C', nil] }).where(:account_id => accountId).where("LOWER(wk_crm_contacts.first_name) like LOWER(?) OR LOWER(wk_crm_contacts.last_name) like LOWER(?)", "%#{contactName}%", "%#{contactName}%")
			end

		elsif contactName.blank? &&  !accountId.blank?
			if accountId == 'AA'
				wkcontact = WkCrmContact.includes(:lead).where(:contact_type => getContactType, wk_leads: { status: ['C', nil] }).where.not(:account_id => nil)
      elsif accountId == 'EV'
        wkcontact = WkCrmContact.includes(:lead).where(:contact_type => getContactType, wk_leads: { status: ['C', nil] })
			else
				wkcontact = WkCrmContact.includes(:lead).where(:contact_type => getContactType, wk_leads: { status: ['C', nil] }).where(:account_id => accountId)
			end

		elsif !contactName.blank? &&  accountId.blank?
			wkcontact = WkCrmContact.includes(:lead).where(:contact_type => getContactType, wk_leads: { status: ['C', nil] }).where(:account_id => nil).where("LOWER(wk_crm_contacts.first_name) like LOWER(?) OR LOWER(wk_crm_contacts.last_name) like LOWER(?)", "%#{contactName}%", "%#{contactName}%")
		else
			wkcontact = WkCrmContact.includes(:lead).where(:contact_type => getContactType, wk_leads: { status: ['C', nil] })
		end

		if !locationId.blank?
			wkcontact = wkcontact.where("wk_crm_contacts.location_id = ? ", locationId.to_i)
		end

    if !params[:address].blank?
      wkcontact = wkcontact.joins(:address).where("LOWER(wk_addresses.address1) LIKE ? OR LOWER(wk_addresses.address2) LIKE ?", "%#{params[:address].downcase}%", "%#{params[:address].downcase}%")
    end

    if !params[:city].blank?
      wkcontact = wkcontact.joins(:address).where("LOWER(wk_addresses.city) LIKE ?", "%#{params[:city].downcase}%")
    end

    if !params[:phone].blank?
      wkcontact = wkcontact.joins(:address).where("LOWER(wk_addresses.work_phone) LIKE ? OR LOWER(wk_addresses.home_phone) LIKE ? OR LOWER(wk_addresses.mobile) LIKE ?", "%#{params[:phone].downcase}%", "%#{params[:phone].downcase}%", "%#{params[:phone].downcase}%")
    end

		formPagination(wkcontact)
	end

	def edit
		@conEditEntry = nil
    @cv_entry_count = {}
    @cv_entry_pages = {}
    @wcf = nil
    @relationDict = nil
    @sort_by = {}
    @filter = {}
    @customValues = {}
		unless params[:contact_id].blank?
			@conEditEntry = WkCrmContact.where(:id => params[:contact_id].to_i)
      @wcf = WkCustomField.where(custom_fields_id: CustomField.where(field_format: "crm_contact"))
      @wcf.map(&:display_as).uniq.each do |section|
        custom_value_entries = @conEditEntry.first.custom_values.where(custom_field_id: WkCustomField.where(display_as: section).map(&:custom_fields_id).uniq)
        sortCustomValuesBy = params["sort_#{section}_by"].nil? ? 'date' : params["sort_#{section}_by"]
        @filter[section]= setCustomValuesFilter(params, section).clone
        @sort_by[section] = sortCustomValuesBy
        customValuesPagination(custom_value_entries, section, sortCustomValuesBy, @filter[section])
      end
      @filter[:current_section] = params[:current_section] unless params[:current_section].nil?
      @relationDict = getRelationDict(@conEditEntry.first())
		end
	end

	def update
		errorMsg = nil
		if params[:contact_id].blank?
		    wkContact = WkCrmContact.new
	    else
		    wkContact = WkCrmContact.find(params[:contact_id].to_i)
	    end
		# For Contact table
		wkContact.assigned_user_id = params[:assigned_user_id]
		wkContact.first_name = params[:first_name]
		wkContact.last_name = params[:last_name]
		wkContact.address_id = params[:address_id]
		wkContact.title = params[:contact_title]
		wkContact.description = params[:description]
		wkContact.department = params[:department]
		wkContact.salutation = params[:salutation]
		wkContact.account_id = nil #params[:account_id]
		wkContact.contact_id = nil
		wkContact.account_id = params[:related_parent] if params[:related_to] == "WkAccount"
		wkContact.contact_id = params[:related_parent] if params[:related_to] == "WkCrmContact"
		wkContact.relationship_id = params[:relationship_id]
		wkContact.location_id = params[:location_id]
		wkContact.contact_type = getContactType
		wkContact.created_by_user_id = User.current.id if wkContact.new_record?
		wkContact.updated_by_user_id = User.current.id
		addrId = updateAddress
		unless addrId.blank?
			wkContact.address_id = addrId
		end
		unless wkContact.valid?
			errorMsg = wkContact.errors.full_messages.join("<br>")
		else
			wkContact.save
		end

		if errorMsg.blank?
			redirect_to :controller => controller_name,:action => 'index' , :tab => controller_name
		    flash[:notice] = l(:notice_successful_update)
		else
			flash[:error] = errorMsg
		    redirect_to :controller => controller_name,:action => 'edit'
		end

	end

	def destroy
    contact = WkCrmContact.find(params[:contact_id].to_i)
    JournalDetail.where(property: "cf", prop_key: CustomField.where(field_format: "crm_contact"), old_value: contact.id).update_all(old_value: "deleted")
    JournalDetail.where(property: "cf", prop_key: CustomField.where(field_format: "crm_contact"), value: contact.id).update_all(value: "deleted")
		if contact.destroy
			flash[:notice] = l(:notice_successful_delete)
		else
			flash[:error] = contact.errors.full_messages.join("<br>")
		end
		redirect_back_or_default :action => 'index', :tab => params[:tab]
	end

	def set_filter_session
    if params[:searchlist].blank? && session[controller_name].nil?
			session[controller_name] = {:contactname => params[:contactname], :account_id => params[:account_id], :location_id => params[:location_id] }
		elsif params[:searchlist] == controller_name
			session[controller_name][:contactname] = params[:contactname]
			session[controller_name][:account_id] = params[:account_id]
			session[controller_name][:location_id] = params[:location_id]
		end
    end

	def formPagination(entries)
		@entry_count = entries.count
		setLimitAndOffset()
		if(sort_column == "last_name")
			@contact = entries.joins(:address).joins(:account).joins("LEFT JOIN users ON users.id = wk_crm_contacts.assigned_user_id").joins("LEFT JOIN wk_locations ON wk_locations.id = wk_accounts.location_id").order("COALESCE(#{sort_column})" + " " + sort_direction + ", first_name asc").limit(@limit).offset(@offset)
		else
			@contact = entries.joins(:address).joins(:account).joins("LEFT JOIN users ON users.id = wk_crm_contacts.assigned_user_id").joins("LEFT JOIN wk_locations ON wk_locations.id = wk_accounts.location_id").order("COALESCE(#{sort_column})" + " " + sort_direction + ", last_name asc, first_name asc").limit(@limit).offset(@offset)
		end
	end

	def setLimitAndOffset
		if api_request?
			@offset, @limit = api_offset_and_limit
			if !params[:limit].blank?
				@limit = params[:limit]
			end
			if !params[:offset].blank?
				@offset = params[:offset]
			end
		else
			@entry_pages = Paginator.new @entry_count, per_page_option, params['page']
			@limit = @entry_pages.per_page
			@offset = @entry_pages.offset
		end
	end

	def getAccountLbl
		l(:label_account)
	end

	def contactLbl
		l(:label_contact_plural)
	end

	private

	def sort_column
		allColumns = [WkCrmContact, WkAccount, WkAddress, WkLocation].flat_map(&:column_names).uniq
		allColumns.push("wk_locations.name", "wk_accounts.name", "users.lastname", "wk_crm_contacts.updated_at")
		allColumns.include?(params[:sort]) ? params[:sort] : "last_name"
	end

	def sort_direction
		%w[asc desc].include?(params[:direction]) ? params[:direction] : "asc"
	end


end
