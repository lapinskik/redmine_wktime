class WkinvoiceController < WkbillingController
  
before_filter :require_login

include WktimeHelper
include WkinvoiceHelper

	def index
		@projects = nil
		set_filter_session
		retrieve_date_range
		accountId = session[:wkinvoice][:account_id]
		projectId	= session[:wkinvoice][:project_id]
		accountProjects = getProjArrays(accountId)
		if @from.blank? && @to.blank?
			@from = Date.civil(Date.today.year, 1, 1)
			@to = Date.civil(Date.today.year, 12, 31)
		end
		@projects = accountProjects.collect{|m| [ m.project_name, m.project_id ] } if !accountProjects.blank?
		unless params[:generate].blank? || !to_boolean(params[:generate])
			if accountId.blank? && projectId.blank?
				allAccounts = WkAccount.all
				allAccounts.each do |account|
					errorMsg = generateInvoices(account.id, projectId, @to + 1, [@from, @to])
				end
			else
				errorMsg = generateInvoices(accountId, projectId, @to + 1, [@from, @to])
			end
			
			if errorMsg.nil?	
				redirect_to :action => 'index' , :tab => 'wkinvoice'
				flash[:notice] = l(:notice_successful_update)
			else
				flash[:error] = errorMsg
				redirect_to :action => 'index'
			end	
		else
			sqlQuery = "select i.id as id, i.invoice_number as invoice_number,  p.name as projectname, a.name as accountname, i.status as status, sum(it.amount) as amount, " +
					   "i.start_date as startdate, i.end_date as enddate, i.invoice_date as invoicedate, i.modifier_id as modifiedby from wk_invoices i " +
					   #"left outer join projects p on p.id = i.project_id " +
					   "left outer join wk_accounts a on a.id = i.account_id " +
					   "left outer join wk_invoice_items it on i.id = it.invoice_id " +
					   " left outer join projects p on p.id = it.project_id " +
					   "left outer join users u on u.id = i.modifier_id " 				
			if !@from.blank? && !@to.blank?
				sqlQuery = sqlQuery + " where i.invoice_date between '#{@from}' and '#{@to}'  "
			end
			if !accountId.blank? && (projectId.blank? || projectId == "0")
				sqlQuery = sqlQuery + " and i.account_id = #{accountId}  "
			end
			
			if accountId.blank? && (!projectId.blank? && projectId != "0")
				sqlQuery = sqlQuery + " and  it.project_id = #{projectId}  "
			end
			
			if !accountId.blank? && (!projectId.blank? &&  projectId != "0")
				sqlQuery = sqlQuery + " and i.account_id = #{accountId} and it.project_id = #{projectId} "
			end
			
			sqlQuery = sqlQuery + "group by i.id"
			findBySql(sqlQuery)
			@total_inc_amt = @invoice_entries.sum { |i| i.amount.blank? ? 0 : i.amount }
		end
	end
	
	
	def edit	
		#query = "select * from wk_invoice_items where invoice_id = #{params[:invoice_id]}  "
		@invoice = WkInvoice.find(params[:invoice_id].to_i)
		 @invoiceItem = @invoice.wk_invoice_items #WkInvoiceItem.where("invoice_id = ? ", params[:invoice_id])
	end
	
	def update
		errorMsg = nil
		invoiceItem = nil
		invItemId = WkInvoiceItem.select(:id).where(:invoice_id => params["invoiceid"].to_i) #, :item_type => 'i'
		arrId = invItemId.map {|i| i.id }
		@invoice = WkInvoice.find(params["invoiceid"].to_i)
		totalAmount = 0
		tothash = Hash.new
		for i in 1..(params[:totalrow].to_i)
			if !params["item_id#{i}"].blank?			
				arrId.delete(params["item_id#{i}"].to_i)
				invoiceItem = WkInvoiceItem.find(params["item_id#{i}"].to_i)
				updatedItem = updateInvoiceItem(invoiceItem, params["project_id#{i}"],  params["name#{i}"], params["rate#{i}"].to_f, params["quantity#{i}"].to_f, invoiceItem.currency)
			else				
				invoiceItem = @invoice.wk_invoice_items.new
				updatedItem = updateInvoiceItem(invoiceItem, params["project_id#{i}"], params["name#{i}"], params["rate#{i}"].to_f, params["quantity#{i}"].to_f, params["currency#{i}"])
			end
			#totalAmount = totalAmount + updatedItem.amount
			tothash[updatedItem.project_id] = [(tothash[updatedItem.project_id].blank? ? 0 : tothash[updatedItem.project_id][0]) + updatedItem.amount, updatedItem.currency]
		end
		
		if !arrId.blank?
			WkInvoiceItem.delete_all(:id => arrId)
		end
		
		accountId = @invoice.account_id		
		tothash.each do|key, val|
			accountProject = WkAccountProject.where("project_id = ?  and account_id = ? ", key, accountId)
			addTaxes(accountProject[0], val[1], val[0])
		end
		
		if errorMsg.nil? 
			redirect_to :action => 'index' , :tab => 'wkinvoice'
			flash[:notice] = l(:notice_successful_update)
	   else
			flash[:error] = errorMsg
			redirect_to :action => 'edit'
	   end
	end
  
    def getAccountProjIds
		accArr = ""	
		accProjId = getProjArrays(params[:account_id])
		if !accProjId.blank?
			accProjId.each do | entry|
				accArr <<  entry.project_id.to_s() + ',' + entry.project_name.to_s()  + "\n" 
			end
		end
		respond_to do |format|
			format.text  { render :text => accArr }
		end
		
    end
	
	def getProjArrays(account_id)		
		sqlStr = "left outer join projects on projects.id = wk_account_projects.project_id "
		if !account_id.blank?
				sqlStr = sqlStr + " where wk_account_projects.account_id = #{account_id} "
		end
		
		WkAccountProject.joins(sqlStr).select("projects.name as project_name, projects.id as project_id")
	end
	
  	def set_filter_session
        if params[:searchlist].blank? && session[:wkinvoice].nil?
			session[:wkinvoice] = {:period_type => params[:period_type],:period => params[:period], :account_id => params[:account_id], :project_id => params[:project_id], :from => @from, :to => @to}
		elsif params[:searchlist] =='wkinvoice'
			session[:wkinvoice][:period_type] = params[:period_type]
			session[:wkinvoice][:period] = params[:period]
			session[:wkinvoice][:from] = params[:from]
			session[:wkinvoice][:to] = params[:to]
			session[:wkinvoice][:account_id] = params[:account_id]
			session[:wkinvoice][:project_id] = params[:project_id]
		end
		
   end
   
   # Retrieves the date range based on predefined ranges or specific from/to param dates
	def retrieve_date_range
		@free_period = false
		@from, @to = nil, nil
		period_type = session[:wkinvoice][:period_type]
		period = session[:wkinvoice][:period]
		fromdate = session[:wkinvoice][:from]
		todate = session[:wkinvoice][:to]
		
		if (period_type == '1' || (period_type.nil? && !period.nil?)) 
		    case period.to_s
			  when 'today'
				@from = @to = Date.today
			  when 'yesterday'
				@from = @to = Date.today - 1
			  when 'current_week'
				@from = getStartDay(Date.today - (Date.today.cwday - 1)%7)
				@to = @from + 6
			  when 'last_week'
				@from =getStartDay(Date.today - 7 - (Date.today.cwday - 1)%7)
				@to = @from + 6
			  when '7_days'
				@from = Date.today - 7
				@to = Date.today
			  when 'current_month'
				@from = Date.civil(Date.today.year, Date.today.month, 1)
				@to = (@from >> 1) - 1
			  when 'last_month'
				@from = Date.civil(Date.today.year, Date.today.month, 1) << 1
				@to = (@from >> 1) - 1
			  when '30_days'
				@from = Date.today - 30
				@to = Date.today
			  when 'current_year'
				@from = Date.civil(Date.today.year, 1, 1)
				@to = Date.civil(Date.today.year, 12, 31)
	        end
		elsif period_type == '2' || (period_type.nil? && (!fromdate.nil? || !todate.nil?))
		    begin; @from = fromdate.to_s.to_date unless fromdate.blank?; rescue; end
		    begin; @to = todate.to_s.to_date unless todate.blank?; rescue; end
		    @free_period = true
		else
		  # default
		  # 'current_month'		
			@from = Date.civil(Date.today.year, Date.today.month, 1)
			@to = (@from >> 1) - 1
	    end    
		
		@from, @to = @to, @from if @from && @to && @from > @to

	end
   
   def findBySql(query)
		result = WkInvoice.find_by_sql("select count(*) as id from (" + query + ") as v2")
	    @entry_count = result.blank? ? 0 : result[0].id
	    setLimitAndOffset()		
	    rangeStr = formPaginationCondition()	
	    @invoice_entries = WkInvoice.find_by_sql(query + rangeStr)
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
	
	def formPaginationCondition
		rangeStr = ""
		if ActiveRecord::Base.connection.adapter_name == 'SQLServer'				
			rangeStr = " OFFSET " + @offset.to_s + " ROWS FETCH NEXT " + @limit.to_s + " ROWS ONLY "
		else		
			rangeStr = " LIMIT " + @limit.to_s +	" OFFSET " + @offset.to_s
		end
		rangeStr
	end

end